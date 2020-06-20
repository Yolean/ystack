#!/bin/sh

mkdir ~/.kube
until test -f /admin/.kube/kubeconfig.yaml; do
  [ $KUBECONFIG_WAIT -gt 0 ] || exit 1
  KUBECONFIG_WAIT=$(( $KUBECONFIG_WAIT - 1 ))
  echo "Waiting for a kubeconfig ..." && sleep 1
done

set -e
cat /admin/.kube/kubeconfig.yaml | sed 's|127.0.0.1|master1|' > ~/.kube/config
kubectl-waitretry --for=condition=Ready node --all

# Might speed up provision, due to the dependency minio -> registry -> builds, but should't be necessary
kubectl apply -f /var/lib/rancher/k3s/server/manifests/ystack-00-ystack-namespace.yaml
kubectl apply -f /var/lib/rancher/k3s/server/manifests/ystack-10-minio.yaml
kubectl-waitretry -n ystack --for=condition=Ready pod minio-0

kubectl apply -f /var/lib/rancher/k3s/server/manifests/

[ -z "$BUILDKITD_REPLICAS" ] || kubectl -n ystack scale --replicas=$BUILDKITD_REPLICAS statefulset/buildkitd

NODE=server
REGISTRY=$(kubectl -n ystack get service builds-registry -o jsonpath={.spec.ports[0].nodePort})
BUILDKIT=$(kubectl -n ystack get service buildkitd-nodeport -o jsonpath={.spec.ports[0].nodePort})
# Assuming ordering is predictable ...
PROMETHEUS=$(kubectl -n ystack get service monitoring-nodeport -o jsonpath={.spec.ports[0].nodePort})
ALERTMANAGER=$(kubectl -n ystack get service monitoring-nodeport -o jsonpath={.spec.ports[1].nodePort})

cat envoy.template.yaml \
  | sed "s|{{ node }}|$NODE|g" \
  | sed "s|{{ registry_nodeport }}|$REGISTRY|g" \
  | sed "s|{{ buildkit_nodeport }}|$BUILDKIT|g" \
  | sed "s|{{ prometheus_nodeport }}|$PROMETHEUS|g" \
  | sed "s|{{ alertmanager_nodeport }}|$ALERTMANAGER|g" \
  > /envoy.yaml

# TODO do we pass on signals?
envoy --config-path /envoy.yaml
