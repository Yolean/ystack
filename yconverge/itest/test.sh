#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -eo pipefail

[ "$1" = "help" ] && echo '
Integration tests for the yconverge framework.
Uses kwok (registry.k8s.io/kwok/cluster) as a lightweight test cluster.

Flags:
  --keep      keep the kwok cluster running after tests
  --teardown  remove a kept cluster and exit

Requires: docker, kubectl, y-cue, kubectl-yconverge
' && exit 0

KEEP=false
TEARDOWN=false
while [ $# -gt 0 ]; do
  case "$1" in
    --keep) KEEP=true; shift ;;
    --teardown) TEARDOWN=true; shift ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# Remove a docker container, tolerating only the "not there" case.
_docker_rm_tolerant() {
  _name="$1"
  if ! _out=$(docker rm -f "$_name" 2>&1); then
    case "$_out" in
      *"No such container"*) ;;
      *) echo "[cue itest] warn: docker rm $_name: $_out" >&2 ;;
    esac
  fi
}

if [ "$TEARDOWN" = "true" ]; then
  echo "[cue itest] Tearing down kept cluster ..."
  _docker_rm_tolerant yconverge-itest
  rm -f /tmp/ystack-yconverge-itest
  echo "[cue itest] Done"
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
YSTACK_HOME="$(cd "$SCRIPT_DIR/../.." && pwd)"
CTX="yconverge-itest"

if [ "$KEEP" = "true" ]; then
  CONTAINER_NAME="yconverge-itest"
  ITEST_KUBECONFIG="/tmp/ystack-yconverge-itest"
else
  CONTAINER_NAME="yconverge-itest-$$"
  ITEST_KUBECONFIG=$(mktemp /tmp/ystack-yconverge-itest.XXXXXX)
fi
export KUBECONFIG="$ITEST_KUBECONFIG"

cleanup() {
  if [ "$KEEP" = "true" ]; then
    echo "[cue itest] KEEP=true, cluster kept:"
    echo "  KUBECONFIG=$ITEST_KUBECONFIG kubectl --context=$CTX get ns"
    return
  fi
  echo "[cue itest] Cleaning up ..."
  _docker_rm_tolerant "$CONTAINER_NAME"
  rm -f "$ITEST_KUBECONFIG"
}
trap cleanup EXIT

echo "[cue itest] yconverge framework integration tests"

# --- start kwok cluster ---

echo "[cue itest] Starting kwok cluster ..."
docker run -d --name "$CONTAINER_NAME" \
  -p 0:8080 \
  registry.k8s.io/kwok/cluster:v0.7.0-k8s.v1.33.0
PORT=$(docker port "$CONTAINER_NAME" 8080 | head -1 | cut -d: -f2)

for i in $(seq 1 30); do
  kubectl --server="http://127.0.0.1:$PORT" get ns default >/dev/null 2>&1 && break
  sleep 1
done

kubectl config set-cluster "$CTX" --server="http://127.0.0.1:$PORT" >/dev/null
kubectl config set-context "$CTX" --cluster="$CTX" >/dev/null
kubectl config set-credentials "$CTX" >/dev/null
kubectl config set-context "$CTX" --user="$CTX" >/dev/null
kubectl config use-context "$CTX" >/dev/null
kubectl --context="$CTX" get ns default >/dev/null 2>&1 \
  && echo "[cue itest] kwok cluster ready at port $PORT" \
  || { echo "[cue itest] FATAL: kwok cluster not reachable"; exit 1; }

# kwok --manage-all-nodes=true only manages nodes that already exist. Without a
# node, pods stay Pending ("no nodes available to schedule pods") and StatefulSet
# status.currentReplicas never advances past the OrderedReady gate. Create one
# fake node so pod-ready stages fire and replica counts reflect spec.
kubectl --context="$CTX" apply -f - <<'YAML' >/dev/null
apiVersion: v1
kind: Node
metadata:
  name: kwok-node-0
  labels:
    kubernetes.io/hostname: kwok-node-0
    type: kwok
status:
  capacity: { cpu: "32", memory: 256Gi, pods: "110" }
  allocatable: { cpu: "32", memory: 256Gi, pods: "110" }
YAML

export CONTEXT="$CTX"

cd "$YSTACK_HOME"

echo "[cue itest] Ensuring tool binaries are available ..."
y-cue version >/dev/null
y-yq --version >/dev/null
kubectl version --client=true >/dev/null 2>&1

# --- schema validation ---

echo ""
echo "[cue itest] CUE schema validation"
y-cue vet ./yconverge/itest/example-namespace/
y-cue vet ./yconverge/itest/example-configmap/
y-cue vet ./yconverge/itest/example-with-dependency/
y-cue vet ./yconverge/itest/example-disabled/
y-cue vet ./yconverge/itest/example-db/single/
y-cue vet ./yconverge/itest/example-db/distributed/

# --- apply with auto-checks ---

echo ""
echo "[cue itest] Apply with auto-checks (namespace)"
kubectl-yconverge --context="$CTX" -k yconverge/itest/example-namespace/

echo ""
echo "[cue itest] Apply with checks (configmap depends on namespace)"
kubectl-yconverge --context="$CTX" -k yconverge/itest/example-configmap/

echo ""
echo "[cue itest] Transitive dependency (depends on configmap which depends on namespace)"
kubectl-yconverge --context="$CTX" -k yconverge/itest/example-with-dependency/

# --- dependency ordering: checks must complete before downstream steps start ---

echo ""
echo "[cue itest] Verify dependency checks serialize before downstream steps"
_DEP_OUT=$(mktemp /tmp/yconverge-itest-deps.XXXXXX)
kubectl-yconverge --context="$CTX" -k yconverge/itest/example-with-dependency/ 2>&1 | tee "$_DEP_OUT"
# namespace check must complete before configmap step begins
_ns_check=$(grep -n 'condition met' "$_DEP_OUT" | head -1 | cut -d: -f1)
_cm_step=$(grep -n '>>> .*example-configmap' "$_DEP_OUT" | cut -d: -f1)
[ "$_ns_check" -lt "$_cm_step" ] \
  || { echo "[cue itest] FAIL: namespace check (line $_ns_check) must complete before configmap step (line $_cm_step)"; exit 1; }
# configmap check must complete before with-dependency step begins
_cm_check=$(grep -n 'configmap exists' "$_DEP_OUT" | head -1 | cut -d: -f1)
_wd_step=$(grep -n '>>> .*example-with-dependency' "$_DEP_OUT" | cut -d: -f1)
[ "$_cm_check" -lt "$_wd_step" ] \
  || { echo "[cue itest] FAIL: configmap check (line $_cm_check) must complete before with-dependency step (line $_wd_step)"; exit 1; }
rm -f "$_DEP_OUT"

# --- indirection with namespace from referenced base ---

echo ""
echo "[cue itest] Indirection: yconverge.cue and namespace from referenced base"
kubectl-yconverge --context="$CTX" -k yconverge/itest/example-indirect/

# --- idempotent re-converge ---

echo ""
echo "[cue itest] Idempotent re-apply"
kubectl-yconverge --context="$CTX" -k yconverge/itest/example-namespace/
kubectl-yconverge --context="$CTX" -k yconverge/itest/example-configmap/

# --- converge-mode labels ---

echo ""
echo "[cue itest] Serverside-force label (other selectors match nothing)"
kubectl-yconverge --context="$CTX" --skip-checks -k yconverge/itest/example-serverside/
kubectl-yconverge --context="$CTX" --skip-checks -k yconverge/itest/example-serverside/

echo ""
echo "[cue itest] replace-mode under --dry-run=server must not delete anything"
kubectl-yconverge --context="$CTX" --skip-checks -k yconverge/itest/example-replace/
_REPLACE_UID_BEFORE=$(kubectl --context="$CTX" -n default get job example-replace-job -o jsonpath='{.metadata.uid}')
_REPLACE_DRY_OUT=$(mktemp /tmp/yconverge-itest-replace.XXXXXX)
kubectl-yconverge --context="$CTX" --skip-checks --dry-run=server -k yconverge/itest/example-replace/ 2>&1 | tee "$_REPLACE_DRY_OUT"
grep -q '(server dry run)' "$_REPLACE_DRY_OUT"
_REPLACE_UID_AFTER=$(kubectl --context="$CTX" -n default get job example-replace-job -o jsonpath='{.metadata.uid}')
[ "$_REPLACE_UID_BEFORE" = "$_REPLACE_UID_AFTER" ] \
  || { echo "[cue itest] FAIL: dry-run deleted/recreated the replace-mode Job (uid $_REPLACE_UID_BEFORE -> $_REPLACE_UID_AFTER)"; exit 1; }
kubectl --context="$CTX" -n default delete job example-replace-job >/dev/null
rm -f "$_REPLACE_DRY_OUT"

_OUT=$(mktemp /tmp/yconverge-itest-out.XXXXXX)

# --- assert: indirection output shows referenced path ---

echo ""
echo "[cue itest] Indirection output must reference the base directory"
kubectl-yconverge --context="$CTX" -k yconverge/itest/example-indirect/ 2>&1 | tee "$_OUT"
grep -q "example-configmap/yconverge.cue" "$_OUT"

# --- negative: --skip-checks suppresses check invocation ---

echo ""
echo "[cue itest] --skip-checks must not produce [yconverge] output"
kubectl-yconverge --context="$CTX" --skip-checks -k yconverge/itest/example-namespace/ 2>&1 | tee "$_OUT"
! grep -q "\[yconverge\]" "$_OUT"

# --- negative: broken yconverge.cue must fail ---

echo ""
echo "[cue itest] Broken yconverge.cue must fail with error message"
mkdir -p /tmp/yconverge-itest-broken
cat > /tmp/yconverge-itest-broken/kustomization.yaml << 'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- configmap.yaml
YAML
cat > /tmp/yconverge-itest-broken/configmap.yaml << 'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: broken-test
  namespace: default
data: {}
YAML
cat > /tmp/yconverge-itest-broken/yconverge.cue << 'CUE'
package broken
this_is_not_valid_cue: !!!
CUE
! kubectl-yconverge --context="$CTX" -k /tmp/yconverge-itest-broken/ 2>&1 | tee "$_OUT"
grep -q "ERROR" "$_OUT"
rm -rf /tmp/yconverge-itest-broken

rm -f "$_OUT"

# --- prod/qa kustomize example ---

# never include namespaces in actual bases as it makes delete -k irreversibe in many cases
kubectl yconverge --context="$CTX" -k yconverge/itest/example-db/namespace/
kubectl yconverge --context="$CTX" -k yconverge/itest/cluster-prod/db/

# cluster-qa/db asserts that no PDB requires more than 1 replica. Applying prod
# first left a PDB with minAvailable: 2 in the namespace, so remove it before
# running qa — recovery step, not a framework feature.
kubectl --context="$CTX" -n db delete pdb database

kubectl yconverge --context="$CTX" -k yconverge/itest/cluster-qa/db/

echo ""
echo "[cue itest] All tests passed"
