#!/bin/bash

# Get absolute path of the script
SCRIPT_PATH="$(readlink -f "$0")"

# TODO restore clean env after sudo troubleshooting
# if [[ "$ENV_IS_CLEAN" != "true" ]]; then
#   exec env -i HOME="$HOME" USER="$USER" LOGNAME="$USER" SHELL="/bin/bash" TERM="$TERM" PATH="/usr/bin:/bin:/usr/sbin:/sbin" ENV_IS_CLEAN=true /bin/bash -lic "$SCRIPT_PATH $*"
#   exit 0
# fi

echo "Acceptance test PATH:"
echo "$PATH"

set -eo pipefail

cleanup() {
  local provisioner
  provisioner=$(y-cluster-local-detect 2>/dev/null) || return 0
  echo "# Cleaning up $provisioner cluster ..."
  y-cluster-provision-$provisioner --teardown || true
}
trap cleanup EXIT

# --- acceptance tests begin here ---

cleanup

ss -tlnp 2>/dev/null | grep -qE ':80 |:443 ' && echo "port 80 and 443 must be available for local cluster to bind to" && exit 1

y-cluster-provision --skip-converge

# --- progressive convergence: proves DAG resolves deps without include/exclude ---

echo ""
echo "# Phase 1: base platform (registry + y-kustomize serving)"
kubectl yconverge --context=local -k k3s/60-builds-registry/

echo ""
echo "# Phase 2: kafka stack (transitive deps through y-kustomize)"
kubectl yconverge --context=local -k k3s/40-kafka/

echo ""
echo "# Phase 3: build infra"
kubectl yconverge --context=local -k k3s/62-buildkit/

echo ""
echo "# Phase 4: prod registry"
kubectl yconverge --context=local -k k3s/61-prod-registry/

echo ""
echo "# Phase 5: monitoring (independent branch)"
kubectl yconverge --context=local -k k3s/50-monitoring/

echo ""
echo "# Phase 6: idempotency proof — re-converge everything"
kubectl yconverge --context=local -k k3s/62-buildkit/
kubectl yconverge --context=local -k k3s/50-monitoring/
kubectl yconverge --context=local -k k3s/61-prod-registry/
kubectl yconverge --context=local -k k3s/40-kafka/

echo ""
echo "# Phase 7: validate the complete stack"
y-cluster-validate-ystack --context=local

echo "Acceptance tests completed"
