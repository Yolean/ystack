#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -eo pipefail

[ "$1" = "help" ] && echo '
Integration tests for the yconverge framework.
Uses kwok (registry.k8s.io/kwok/cluster) as a lightweight test cluster.

Flags:
  --keep    keep the kwok cluster running after tests

Requires: docker, kubectl, y-cue, kubectl-yconverge
' && exit 0

KEEP=false
while [ $# -gt 0 ]; do
  case "$1" in
    --keep) KEEP=true; shift ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
YSTACK_HOME="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONTAINER_NAME="yconverge-itest-$$"
CTX="yconverge-itest"

cleanup() {
  if [ "$KEEP" = "true" ]; then
    echo "[cue itest] KEEP=true, cluster kept: kubectl --context=$CTX get ns"
    return
  fi
  echo "[cue itest] Cleaning up ..."
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true # y-script-lint:disable=or-true # best-effort cleanup
  kubectl config delete-context "$CTX" 2>/dev/null || true # y-script-lint:disable=or-true # best-effort cleanup
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
kubectl --context="$CTX" get ns default >/dev/null 2>&1 \
  && echo "[cue itest] kwok cluster ready at port $PORT" \
  || { echo "[cue itest] FATAL: kwok cluster not reachable"; exit 1; }

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

echo ""
echo "[cue itest] All tests passed"
