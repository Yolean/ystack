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
    BLOBSTORE="${BLOBSTORE:-}" \
    /bin/bash -lic "$SCRIPT_PATH $*"

  exit 0
fi

echo "Acceptance test PATH:"
echo "$PATH"

set -eo pipefail

CONFIG=cluster-configs/local-docker

# Blobstore selection. Default versitygw (ystack's default); set
# BLOBSTORE=minio to swap in the parallel minio bases. Picked up
# below to choose the registry/buildkit converge entry points and
# is exported so y-cluster-validate-ystack swaps its deploy/<x>
# checks in lockstep.
BLOBSTORE="${BLOBSTORE:-versitygw}"
case "$BLOBSTORE" in
  versitygw)
    REGISTRY_BASE=k3s/60-builds-registry
    BUILDKIT_BASE=k3s/62-buildkit
    ;;
  minio)
    REGISTRY_BASE=k3s/60-builds-registry-minio-disabled
    BUILDKIT_BASE=k3s/62-buildkit-minio-disabled
    ;;
  *)
    echo "Unknown BLOBSTORE: $BLOBSTORE (expected: versitygw | minio)" >&2
    exit 1
    ;;
esac
export BLOBSTORE
echo "# BLOBSTORE=$BLOBSTORE -> registry=$REGISTRY_BASE buildkit=$BUILDKIT_BASE"

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
}
trap cleanup EXIT

# --- acceptance tests begin here ---

cleanup

# --- provision (no converge) ---
#
# y-cluster v0.3.5 added a host-side /readyz probe between the
# in-container kubeconfig appearing and "k3s ready" being declared,
# closing the docker port-forward race that made the next step
# (envoy-gateway install via kubectl apply) fail with "dial tcp
# 127.0.0.1:6443: connect: connection refused" (Yolean/y-cluster#12).
# v0.3.6 fixed a separate silent-drop in the docker provider where
# moby v1.54+ sent every PortBinding's HostIp as the empty string
# (zero netip.Addr) and Docker Engine 28 dropped them all, so
# NetworkSettings.Ports came back empty (Yolean/y-cluster#15).
# v0.3.7 mirrors PortBindings into Config.ExposedPorts to match
# `docker run -p` semantics (Yolean/y-cluster#17), addressing the
# remaining ubuntu-latest case where Engine 28 still dropped
# bindings even after the HostIP fix (Yolean/y-cluster#16).
y-cluster provision -c "$CONFIG"

# Label nodes that don't yet have a cluster identity. Selector form
# avoids overwriting an existing label on a misclaimed cluster.
kubectl --context=local label nodes -l '!yolean.se/cluster' yolean.se/cluster=local

# buckety-controller image is built locally (contain) and not yet
# pushed to a registry. Sideload the OCI layout into the cluster's
# containerd so kubelet finds it by tag at IfNotPresent.
# Override with $BUCKETY_CONTROLLER_OCI if the repo lives elsewhere.
BUCKETY_CONTROLLER_OCI="${BUCKETY_CONTROLLER_OCI:-$HOME/Yolean/buckety-controller/oci}"
if [ -d "$BUCKETY_CONTROLLER_OCI" ]; then
  echo ""
  echo "# Sideload buckety-controller from $BUCKETY_CONTROLLER_OCI"
  y-cluster images load "$BUCKETY_CONTROLLER_OCI" --context=local
else
  echo "ERROR: buckety-controller OCI layout not found at $BUCKETY_CONTROLLER_OCI;" >&2
  echo "       build it with (in that repo): contain build --output ./oci --push=false" >&2
  exit 1
fi

# --- gateway: just the consumer Gateway resource (CRDs + GatewayClass come from y-cluster provision) ---

echo ""
echo "# ystack Gateway resource"
y-cluster yconverge --context=local -k k3s/20-gateway/

# --- progressive convergence: proves DAG resolves deps without include/exclude ---

echo ""
echo "# Phase 1: base platform (registry + buckety-provisioned kafka topic and S3 bucket)"
y-cluster yconverge --context=local -k "$REGISTRY_BASE/"

echo ""
echo "# Phase 2: kafka stack"
y-cluster yconverge --context=local -k k3s/40-kafka/

echo ""
echo "# Phase 3: build infra"
y-cluster yconverge --context=local -k "$BUILDKIT_BASE/"

echo ""
echo "# Phase 4: prod registry"
y-cluster yconverge --context=local -k k3s/61-prod-registry/

echo ""
echo "# Phase 5: monitoring (independent branch)"
y-cluster yconverge --context=local -k k3s/50-monitoring/

echo ""
echo "# Phase 6: idempotency proof -- re-converge everything"
y-cluster yconverge --context=local -k "$BUILDKIT_BASE/"
y-cluster yconverge --context=local -k k3s/50-monitoring/
y-cluster yconverge --context=local -k k3s/61-prod-registry/
y-cluster yconverge --context=local -k k3s/40-kafka/

echo ""
echo "# Phase 7: validate the complete stack"
y-cluster-validate-ystack --context=local

echo "Acceptance tests completed"
