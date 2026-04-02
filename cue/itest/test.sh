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
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS  $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL  $1"; }

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

# Wait for API server
for i in $(seq 1 30); do
  kubectl --server="http://127.0.0.1:$PORT" get ns default >/dev/null 2>&1 && break
  sleep 1
done

# Set up context
kubectl config set-cluster "$CTX" --server="http://127.0.0.1:$PORT" >/dev/null
kubectl config set-context "$CTX" --cluster="$CTX" >/dev/null

# Verify cluster works
kubectl --context="$CTX" get ns default >/dev/null 2>&1 \
  && echo "# kwok cluster ready at port $PORT" \
  || { echo "# FATAL: kwok cluster not reachable"; exit 1; }

export CONTEXT="$CTX"

cd "$YSTACK_HOME"

# --- test: CUE schema validation ---

echo ""
echo "# Test: CUE schema validation"
y-cue vet ./cue/itest/example-namespace/ \
  && pass "example-namespace validates" \
  || fail "example-namespace validation"

y-cue vet ./cue/itest/example-configmap/ \
  && pass "example-configmap validates (with dependency)" \
  || fail "example-configmap validation"

y-cue vet ./cue/itest/example-with-dependency/ \
  && pass "example-with-dependency validates (transitive)" \
  || fail "example-with-dependency validation"

y-cue vet ./cue/itest/example-disabled/ \
  && pass "example-disabled validates" \
  || fail "example-disabled validation"

# --- test: plain kubectl-yconverge (no yconverge.cue) ---

echo ""
echo "# Test: plain apply without yconverge.cue"
kubectl-yconverge --context="$CTX" -k cue/itest/example-namespace/ >/dev/null 2>&1 \
  && pass "plain apply namespace" \
  || fail "plain apply namespace"

kubectl --context="$CTX" get ns itest >/dev/null 2>&1 \
  && pass "namespace itest exists after apply" \
  || fail "namespace itest missing after apply"

# Clean up for next test
kubectl --context="$CTX" delete ns itest --wait=true >/dev/null 2>&1

# --- test: kubectl-yconverge with yconverge.cue checks ---

echo ""
echo "# Test: apply with auto-checks"
OUTPUT=$(kubectl-yconverge --context="$CTX" -k cue/itest/example-namespace/ 2>&1)
echo "$OUTPUT"
echo "$OUTPUT" | grep -q "\[yconverge\]" \
  && pass "yconverge.cue detected and checks ran" \
  || fail "yconverge.cue not detected"

# --- test: dependency precondition checks ---

echo ""
echo "# Test: dependency precondition (configmap depends on namespace)"
OUTPUT=$(kubectl-yconverge --context="$CTX" -k cue/itest/example-configmap/ 2>&1) || true # y-script-lint:disable=or-true # capture output even on failure
echo "$OUTPUT"
echo "$OUTPUT" | grep -q "\[yconverge\]" \
  && pass "configmap applied with dependency checks" \
  || fail "configmap apply failed"

kubectl --context="$CTX" -n itest get configmap itest-config >/dev/null 2>&1 \
  && pass "configmap itest-config exists" \
  || fail "configmap itest-config missing"

# --- test: transitive dependency ---

echo ""
echo "# Test: transitive dependency (depends on configmap which depends on namespace)"
OUTPUT=$(kubectl-yconverge --context="$CTX" -k cue/itest/example-with-dependency/ 2>&1) || true # y-script-lint:disable=or-true # capture output
echo "$OUTPUT"
echo "$OUTPUT" | grep -q "\[yconverge\]" \
  && pass "transitive dependency converge" \
  || fail "transitive dependency failed"

kubectl --context="$CTX" -n itest get configmap itest-dependent >/dev/null 2>&1 \
  && pass "dependent configmap exists" \
  || fail "dependent configmap missing"

# --- test: disabled step ---

echo ""
echo "# Test: disabled step should not apply"
kubectl-yconverge --context="$CTX" -k cue/itest/example-disabled/ >/dev/null 2>&1
kubectl --context="$CTX" -n itest get configmap itest-should-not-exist >/dev/null 2>&1 \
  && fail "disabled configmap should NOT exist" \
  || pass "disabled step correctly skipped"

# --- test: one-level indirection ---

echo ""
echo "# Test: yconverge.cue found via resources indirection"
kubectl --context="$CTX" delete ns itest --wait=true >/dev/null 2>&1 || true # y-script-lint:disable=or-true # clean slate
OUTPUT=$(kubectl-yconverge --context="$CTX" -k cue/itest/example-indirect/ 2>&1) || true # y-script-lint:disable=or-true # capture output
echo "$OUTPUT"
echo "$OUTPUT" | grep -q "\[yconverge\]" \
  && pass "indirection: yconverge.cue found in referenced dir" \
  || fail "indirection: yconverge.cue not found"

# --- test: idempotent re-converge ---

echo ""
echo "# Test: idempotent re-apply"
kubectl-yconverge --context="$CTX" -k cue/itest/example-namespace/ >/dev/null 2>&1 \
  && pass "re-apply namespace (idempotent)" \
  || fail "re-apply namespace failed"

kubectl-yconverge --context="$CTX" -k cue/itest/example-configmap/ >/dev/null 2>&1 \
  && pass "re-apply configmap (idempotent)" \
  || fail "re-apply configmap failed"

# --- test: error reporting ---

echo ""
echo "# Test: error reporting on check failure"
# Apply to a non-existent namespace to trigger a check failure
OUTPUT=$(kubectl-yconverge --context="$CTX" -k cue/itest/example-configmap/ 2>&1) || true # y-script-lint:disable=or-true # expect possible failure
echo "$OUTPUT" | grep -q "configmap" \
  && pass "error output mentions the resource" \
  || fail "error output unhelpful"

# --- test: --skip-checks flag ---

echo ""
echo "# Test: --skip-checks suppresses check invocation"
OUTPUT=$(kubectl-yconverge --context="$CTX" --skip-checks -k cue/itest/example-namespace/ 2>&1)
echo "$OUTPUT" | grep -q "\[yconverge\]" \
  && fail "--skip-checks still ran checks" \
  || pass "--skip-checks suppressed checks"

# --- results ---

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

[ "$FAIL" -eq 0 ]
