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

# --- acceptance tests begin here ---

y-cluster-local-detect && (echo "tear down existing local cluster first" && exit 1) || true

ss -tlnp 2>/dev/null | grep -qE ':80 |:443 ' && echo "port 80 and 443 must be available for local cluster to bind to" && exit 1

y-cluster-provision-k3d --teardown
y-cluster-provision-k3d
y-cluster-validate-ystack --context=local

y-cluster-provision-k3d --teardown

echo "Acceptance tests completed"
