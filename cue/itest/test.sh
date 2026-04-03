#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -eo pipefail

[ "$1" = "help" ] && echo '
Integration tests for the yconverge framework.
Uses kwok (registry.k8s.io/kwok/cluster) as a lightweight test cluster.

Requires: docker, kubectl, y-cue, kubectl-yconverge
' && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
YSTACK_HOME="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONTAINER_NAME="yconverge-itest-$$"
CTX="yconverge-itest"

cleanup() {
  echo "# Cleaning up ..."
  docker rm -f "$CONTAINER_NAME" 2>/dev/null || true # y-script-lint:disable=or-true # best-effort cleanup
  kubectl config delete-context "$CTX" 2>/dev/null || true # y-script-lint:disable=or-true # best-effort cleanup
}
trap cleanup EXIT

echo "=== yconverge framework integration tests ==="

# --- start kwok cluster ---

echo "# Starting kwok cluster ..."
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
  && echo "# kwok cluster ready at port $PORT" \
  || { echo "# FATAL: kwok cluster not reachable"; exit 1; }

export CONTEXT="$CTX"

cd "$YSTACK_HOME"

echo "# Ensuring tool binaries are available ..."
y-cue version >/dev/null
y-yq --version >/dev/null
kubectl version --client=true >/dev/null 2>&1

# --- schema validation ---

echo ""
echo "# CUE schema validation"
y-cue vet ./cue/itest/example-namespace/
y-cue vet ./cue/itest/example-configmap/
y-cue vet ./cue/itest/example-with-dependency/
y-cue vet ./cue/itest/example-disabled/

# --- apply with auto-checks ---

echo ""
echo "# Apply with auto-checks (namespace)"
kubectl-yconverge --context="$CTX" -k cue/itest/example-namespace/

echo ""
echo "# Apply with checks (configmap depends on namespace)"
kubectl-yconverge --context="$CTX" -k cue/itest/example-configmap/

echo ""
echo "# Transitive dependency (depends on configmap which depends on namespace)"
kubectl-yconverge --context="$CTX" -k cue/itest/example-with-dependency/

# --- indirection with namespace from referenced base ---

echo ""
echo "# Indirection: yconverge.cue and namespace from referenced base"
kubectl-yconverge --context="$CTX" -k cue/itest/example-indirect/

# --- idempotent re-converge ---

echo ""
echo "# Idempotent re-apply"
kubectl-yconverge --context="$CTX" -k cue/itest/example-namespace/
kubectl-yconverge --context="$CTX" -k cue/itest/example-configmap/

# --- multiple -k args ---

echo ""
echo "# Multiple -k args"
kubectl --context="$CTX" delete ns itest --wait=true >/dev/null 2>&1 || true # y-script-lint:disable=or-true # clean slate
kubectl-yconverge --context="$CTX" \
  -k cue/itest/example-namespace/ \
  -k cue/itest/example-configmap/ \
  -k cue/itest/example-with-dependency/

# --- converge-mode labels ---

echo ""
echo "# Serverside-force label (other selectors match nothing)"
kubectl-yconverge --context="$CTX" --skip-checks -k cue/itest/example-serverside/
kubectl-yconverge --context="$CTX" --skip-checks -k cue/itest/example-serverside/

# --- negative: --skip-checks suppresses check invocation ---

echo ""
echo "# --skip-checks must not produce [yconverge] output"
! kubectl-yconverge --context="$CTX" --skip-checks -k cue/itest/example-namespace/ 2>&1 | grep -q "\[yconverge\]"

# --- negative: broken yconverge.cue must fail ---

echo ""
echo "# Broken yconverge.cue must fail"
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
! kubectl-yconverge --context="$CTX" -k /tmp/yconverge-itest-broken/
rm -rf /tmp/yconverge-itest-broken

echo ""
echo "=== All tests passed ==="
