#!/bin/bash

# Get absolute path of the script
SCRIPT_PATH="$(readlink -f "$0")"

if [[ "$ENV_IS_CLEAN" != "true" ]]; then
  echo "Mirroring a fresh interactive terminal..."

  exec env -i \
    HOME="$HOME" \
    USER="$USER" \
    LOGNAME="$USER" \
    SHELL="/bin/bash" \
    TERM="$TERM" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    ENV_IS_CLEAN=true \
    /bin/bash -lic "$SCRIPT_PATH $*"

  exit 0
fi

echo "Acceptance test PATH:"
echo "$PATH"

set -eo pipefail

CONFIG=cluster-configs/local-qemu

# qemu cluster is reachable from the host via 127.0.0.1; ystack's Gateway
# /etc/hosts logic respects this annotation when set.
export OVERRIDE_IP=127.0.0.1

cleanup() {
  echo "# Cleaning up cluster ..."
  y-cluster teardown -c "$CONFIG" || true # y-script-lint:disable=or-true # best-effort cleanup in EXIT trap
}
trap cleanup EXIT

# --- acceptance tests begin here ---

cleanup

# --- provision (no converge) ---

y-cluster provision -c "$CONFIG"

# Label nodes that don't yet have a cluster identity. Selector form
# avoids overwriting an existing label on a misclaimed cluster.
kubectl --context=local label nodes -l '!yolean.se/cluster' yolean.se/cluster=local

# --- gateway api setup (until y-cluster provision installs Envoy Gateway, see specs/y-cluster/SPEC.md) ---

echo ""
echo "# Gateway API CRDs + traefik provider"
y-cluster yconverge --context=local -k k3s/10-gateway-api/

echo ""
echo "# ystack Gateway resource"
y-cluster yconverge --context=local -k k3s/20-gateway/

# --- progressive convergence: proves DAG resolves deps without include/exclude ---

echo ""
echo "# Phase 1: base platform (registry + y-kustomize serving)"
y-cluster yconverge --context=local -k k3s/60-builds-registry/

echo ""
echo "# Phase 2: kafka stack (transitive deps through y-kustomize)"
y-cluster yconverge --context=local -k k3s/40-kafka/

echo ""
echo "# Phase 3: build infra"
y-cluster yconverge --context=local -k k3s/62-buildkit/

echo ""
echo "# Phase 4: prod registry"
y-cluster yconverge --context=local -k k3s/61-prod-registry/

echo ""
echo "# Phase 5: monitoring (independent branch)"
y-cluster yconverge --context=local -k k3s/50-monitoring/

echo ""
echo "# Phase 6: idempotency proof -- re-converge everything"
y-cluster yconverge --context=local -k k3s/62-buildkit/
y-cluster yconverge --context=local -k k3s/50-monitoring/
y-cluster yconverge --context=local -k k3s/61-prod-registry/
y-cluster yconverge --context=local -k k3s/40-kafka/

echo ""
echo "# Phase 7: validate the complete stack"
y-cluster-validate-ystack --context=local

echo "Acceptance tests completed"
