#!/bin/zsh

# Get absolute path of the script
SCRIPT_PATH="${0:A}"

if [[ "$ENV_IS_CLEAN" != "true" ]]; then
  echo " Mirroring a fresh interactive terminal..."

  # We pass a basic PATH so path_helper and your scripts have a starting point.
  # We use -ilc:
  # -l: Login (loads /etc/zprofile, ~/.zprofile)
  # -i: Interactive (bypasses '[[ -z "$PS1" ]] && return' guards)
  # -c: Command (executes this script)
  exec env -i \
    HOME="$HOME" \
    USER="$USER" \
    LOGNAME="$USER" \
    SHELL="/bin/zsh" \
    TERM="$TERM" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    ENV_IS_CLEAN=true \
    /bin/zsh -ilc "$SCRIPT_PATH $*"

  exit 0
fi

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

lsof -iTCP:80 -iTCP:443 -sTCP:LISTEN -P -n >/dev/null 2>&1 && echo "port 80 and 443 must be available for local cluster vm to bind to" && exit 1

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
