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
y-cluster-provision-k3d
y-cluster-validate-ystack --context=local

echo "Acceptance tests completed"
