#!/bin/zsh

# Get absolute path of the script
SCRIPT_PATH="${0:A}"

if [[ "$ENV_IS_CLEAN" != "true" ]]; then
  echo " Mirroring a fresh interactive terminal..."

  # We pass a basic PATH so path_helper and your scripts have a starting point.
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

# macOS arm64: Docker Desktop runs amd64 images via emulation today, so
# this test exercises the same flow as -osx-amd64.
CONFIG=cluster-configs/local-docker

cleanup() {
  echo "# Cleaning up cluster ..."
  y-cluster teardown -c "$CONFIG" || true # y-script-lint:disable=or-true # best-effort cleanup in EXIT trap
}
trap cleanup EXIT

cleanup

lsof -iTCP:80 -iTCP:443 -sTCP:LISTEN -P -n >/dev/null 2>&1 && echo "port 80 and 443 must be available for local cluster vm to bind to" && exit 1

y-cluster provision -c "$CONFIG"

kubectl --context=local label nodes -l '!yolean.se/cluster' yolean.se/cluster=local

y-cluster yconverge --context=local -k k3s/20-gateway/

# Progressive convergence
y-cluster yconverge --context=local -k k3s/60-builds-registry/
y-cluster yconverge --context=local -k k3s/40-kafka/
y-cluster yconverge --context=local -k k3s/62-buildkit/
y-cluster yconverge --context=local -k k3s/61-prod-registry/
y-cluster yconverge --context=local -k k3s/50-monitoring/

# Idempotency
y-cluster yconverge --context=local -k k3s/62-buildkit/
y-cluster yconverge --context=local -k k3s/50-monitoring/
y-cluster yconverge --context=local -k k3s/61-prod-registry/
y-cluster yconverge --context=local -k k3s/40-kafka/

y-cluster-validate-ystack --context=local

echo "Acceptance tests completed"
