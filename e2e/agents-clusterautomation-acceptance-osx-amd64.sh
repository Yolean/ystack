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

# macOS path uses the docker provider via Docker Desktop (no KVM).
# Multipass and Lima provisioners aren't supported by y-cluster yet; once
# they ship in the binary we can either add cluster-configs/local-{lima,multipass}
# or run them through the same docker config here.
CONFIG=cluster-configs/local-docker

cleanup() {
  echo "# Cleaning up cluster ..."
  y-cluster teardown -c "$CONFIG" || true # y-script-lint:disable=or-true # best-effort cleanup in EXIT trap
}
trap cleanup EXIT

# --- acceptance tests begin here ---

cleanup

lsof -iTCP:80 -iTCP:443 -sTCP:LISTEN -P -n >/dev/null 2>&1 && echo "port 80 and 443 must be available for local cluster vm to bind to" && exit 1

y-cluster provision -c "$CONFIG"

# Label nodes that don't yet have a cluster identity.
kubectl --context=local label nodes -l '!yolean.se/cluster' yolean.se/cluster=local

y-cluster yconverge --context=local -k k3s/10-gateway-api/
y-cluster yconverge --context=local -k k3s/20-gateway/

y-cluster-validate-ystack --context=local

echo "Acceptance tests completed"
