#!/usr/bin/env bash

set -e

[ -z "$VM_NAME" ] && VM_NAME="ystack"
[ -z "$VM_RESOURCES" ] && VM_RESOURCES="-m 8G -d 40G -c 4"
[ -z "$K8S_CHANNEL" ] && K8S_CHANNEL="1.14/stable"

if ! multipass info "$VM_NAME" 2>/dev/null
then
  multipass launch -n "$VM_NAME" $VM_RESORCES
fi

multipass exec "$VM_NAME" -- sudo K8S_CHANNEL=$K8S_CHANNEL bash -cex '

function kubectl() {
  microk8s.kubectl "$@"
}

sudo snap install --channel=$K8S_CHANNEL --classic microk8s

# Facilitate local registry access using the same address in cluster (knative, buildkit, kaniko etc) and containerd (pod image pull)
# The registry addon in microk8s does not meet that requirement
# SSL
if ! [ -f /usr/local/share/ca-certificates/microk8s-local-ca.crt ]
then
  ln -s /var/snap/microk8s/current/certs/ca.crt /usr/local/share/ca-certificates/microk8s-local-ca.crt
  update-ca-certificates
fi
# NodePort
grep registry.svc.cluster.local /var/snap/microk8s/current/args/containerd-template.toml || sed -i "s|      \[plugins.cri.registry.mirrors\]|      [plugins.cri.registry.mirrors]\\
        [plugins.cri.registry.mirrors.\"builds.registry.svc.cluster.local\"]\\
          endpoint = [\"http://localhost:32050\"]\\
        [plugins.cri.registry.mirrors.\"prod.registry.svc.cluster.local\"]\\
          endpoint = [\"http://localhost:32055\"]|" /var/snap/microk8s/current/args/containerd-template.toml 
# Both of the above require containerd restart (or even microk8s restart?)
systemctl reload-or-restart snap.microk8s.daemon-containerd

while ! microk8s.kubectl wait --for=condition=ready --all nodes
do
  echo "Waiting for k8s to be available again after restart"
  sleep 1
done
! grep registry.svc.cluster.local -A 1 /var/snap/microk8s/current/args/containerd.toml && echo "Containerd config template failed to propagate to effective" && false

microk8s.enable dns
microk8s.kubectl wait --timeout=120s --for condition=ready -n kube-system pods -l k8s-app=kube-dns

microk8s.enable ingress
'

if [ ! -z "$KUBECONFIG" ] && [ ! -f "$KUBECONFIG" ]
then
  (multipass exec "$VM_NAME" -- /snap/bin/microk8s.config) > $KUBECONFIG
  echo "Created KUBECONFIG=$KUBECONFIG"
fi
