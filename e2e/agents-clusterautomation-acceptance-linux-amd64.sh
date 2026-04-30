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
  y-cluster teardown -c "$CONFIG" || true # y-script-lint:disable=or-true # best-effort cleanup in EXIT trap
  # The acceptance flow uses the in-cluster y-kustomize Deployment via
  # the qemu hostfwd 8944. If 8944 is still bound on the host after
  # teardown, a leftover host-local `y-cluster serve` from a downstream
  # user's run (or a developer poking at bin/acceptance-y-kustomize-local)
  # would block the next provision's hostfwd from binding. Probe and
  # best-effort stop -- not fatal if the binding is something else
  # entirely.
  if ss -lnt 'sport = :8944' 2>/dev/null | grep -q ':8944 '; then
    echo "# Port 8944 still in use; attempting host-local y-cluster serve stop"
    y-cluster serve stop || true # y-script-lint:disable=or-true # best-effort
  fi
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

# --- y-kustomize served by the in-cluster Deployment (no host-local serve) ---
#
# k3s/29-y-kustomize applies a LoadBalancer Service on port 8944 that
# ServiceLB binds on the node. cluster-configs/local-qemu/y-cluster-provision.yaml
# adds host:8944 -> guest:8944 to PortForwards, so the host reaches the
# in-cluster Deployment via 127.0.0.1:8944. /etc/hosts maps
# `y-kustomize -> 127.0.0.1` (y-k8s-ingress-hosts walks the dummy
# y-kustomize HTTPRoute hostname).
#
# Downstream users that want to run y-cluster serve locally can do so
# via `y-cluster serve -c y-kustomize/` -- see
# bin/acceptance-y-kustomize-local for the standalone test of that path.

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
