#!/bin/sh

mkdir ~/.kube
until test -f /admin/.kube/kubeconfig.yaml; do
  [ $KUBECONFIG_WAIT -gt 0 ] || exit 1
  KUBECONFIG_WAIT=$(( $KUBECONFIG_WAIT - 1 ))
  echo "Waiting for a kubeconfig ..." && sleep 1
done

set -e
cat /admin/.kube/kubeconfig.yaml | sed 's|127.0.0.1|server|' > ~/.kube/config
kubectl-waitretry --for=condition=Ready node --all

kubectl -n ystack apply -f /var/lib/rancher/k3s/server/manifests/

NODE=agent
NODEPORT=$(kubectl -n ystack get service builds-registry -o jsonpath={.spec.ports[0].nodePort})

cat envoy.template.yaml \
  | sed "s|{{ node }}|$NODE|g" \
  | sed "s|{{ nodeport }}|$NODEPORT|g" \
  > /envoy.yaml

# TODO do we pass on signals?
envoy --config-path /envoy.yaml
