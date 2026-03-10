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
y-cluster-provision-k3d
y-cluster-validate-ystack --context=local

echo "Acceptance tests completed"
