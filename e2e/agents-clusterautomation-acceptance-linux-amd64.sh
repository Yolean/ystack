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

# Host reachability flows from y-cluster's yolean.se/dns-hint-ip
# annotation on the installed GatewayClass: when guest:80 is in
# PortForwards (qemu and docker default), provision stamps
# 127.0.0.1 there, and y-k8s-ingress-hosts walks
# Gateway -> gatewayClassName -> GatewayClass annotation to find
# it. No env var, no per-cluster operator setup.

KEEP_ON_FAILURE=false
while [ $# -gt 0 ]; do
  case "$1" in
    --keep-on-failure) KEEP_ON_FAILURE=true; shift ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

cleanup() {
  local rc=$?
  if [ "$KEEP_ON_FAILURE" = "true" ] && [ "$rc" -ne 0 ]; then
    echo "# Acceptance failed (rc=$rc); cluster left up for inspection."
    echo "# Manual cleanup: y-cluster teardown -c $CONFIG"
    return
  fi
  # Default: teardown on every EXIT (success or failure).
  # FUTURE: the default is intended to become "keep cluster on
  # failure for a configurable number of minutes, then teardown" --
  # a window for post-mortem inspection without leaving stale VMs
  # around forever. --keep-on-failure is the manual opt-in until
  # that timed-keep mode lands.
  echo "# Cleaning up cluster ..."
  y-cluster serve stop || true # y-script-lint:disable=or-true # best-effort
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

# --- gateway: just the consumer Gateway resource (CRDs + GatewayClass come from y-cluster provision) ---

echo ""
echo "# ystack Gateway resource"
y-cluster yconverge --context=local -k k3s/20-gateway/

# --- y-cluster serve on the host, until the in-cluster v0.3.0 image ships ---
#
# k3s/29-y-kustomize/yconverge.cue probes http://y-kustomize:8944/health.
# The probe resolves through /etc/hosts (y-kustomize -> 127.0.0.1) and
# either the in-cluster Deployment OR a host-local `y-cluster serve`
# answers. v0.3.0 isn't released yet, so the in-cluster Deployment will
# ImagePullBackOff. We start serve here on the host so the same probe
# passes against the same /v1/{group}/{name}/{key} URLs.
#
# When v0.3.0 ships and the in-cluster Deployment rolls out, this block
# can be deleted without changes to bases or yconverge.cue files.
echo ""
echo "# Starting host-local y-cluster serve"
y-cluster serve ensure -c y-kustomize/

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
