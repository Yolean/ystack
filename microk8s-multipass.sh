#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -e

[ -z "$VM_NAME" ] && VM_NAME="ystack"
[ -z "$VM_RESOURCES" ] && VM_RESOURCES="-m 8G -d 40G -c 4"
[ -z "$K8S_CHANNEL" ] && K8S_CHANNEL="1.14/stable"

if ! multipass info "$VM_NAME" 2>/dev/null
then
  multipass launch -n "$VM_NAME" $VM_RESOURCES
fi

echo "# VM_NAME=\"$VM_NAME\" found. The rest of this script runs inside the VM."

multipass exec "$VM_NAME" -- sudo K8S_CHANNEL=$K8S_CHANNEL bash -cex '

sudo snap install --channel=$K8S_CHANNEL --classic microk8s

# Facilitate local registry access using the same address in cluster (knative, buildkit, kaniko etc) and containerd (pod image pull)
# The registry addon in microk8s does not meet that requirement
# SSL
if ! [ -f /usr/local/share/ca-certificates/microk8s-local-ca.crt ]
then
  ln -s /var/snap/microk8s/current/certs/ca.crt /usr/local/share/ca-certificates/microk8s-local-ca.crt
  update-ca-certificates
  CONTANIERD_RESTART=true
fi
# Registry /etc/hosts update but plain http instead of implicit https
if ! grep registry.svc.cluster.local /var/snap/microk8s/current/args/containerd-template.toml
then
  sed -i "s|      \[plugins.cri.registry.mirrors\]|      [plugins.cri.registry.mirrors]\\
        [plugins.cri.registry.mirrors.\"builds-registry.ystack.svc.cluster.local\"]\\
          endpoint = [\"http://builds-registry.ystack.svc.cluster.local\"]\\
        [plugins.cri.registry.mirrors.\"prod-registry.ystack.svc.cluster.local\"]\\
          endpoint = [\"http://prod-registry.ystack.svc.cluster.local\"]|" /var/snap/microk8s/current/args/containerd-template.toml
  CONTANIERD_RESTART=true
fi

if [ "$CONTANIERD_RESTART" = "true" ]
then
  echo "Restarting Containerd due to config changes"
  systemctl reload-or-restart snap.microk8s.daemon-containerd
fi

while ! microk8s.kubectl wait --for=condition=ready --all nodes
do
  echo "Waiting for k8s to be available again after restart"
  sleep 1
done
! grep registry.svc.cluster.local -A 1 /var/snap/microk8s/current/args/containerd.toml && ls -l /var/snap/microk8s/current/args/containerd* && echo "Containerd config template failed to propagate to effective" && false

if ! microk8s.kubectl -n kube-system wait --timeout=1s --for=condition=ready pods -l k8s-app=kube-dns
then
  microk8s.enable dns
  sleep 10
  microk8s.kubectl wait --timeout=120s --for condition=ready -n kube-system pods -l k8s-app=kube-dns
fi

if ! microk8s.kubectl -n default wait --timeout=1s --for=condition=ready pods -l name=nginx-ingress-microk8s
then
  microk8s.enable ingress
fi

if ! microk8s.kubectl -n kube-system wait --timeout=1s --for=condition=ready pods -l k8s-app=hostpath-provisioner
then
  microk8s.enable storage
  cat << EOF | microk8s.kubectl create -f -
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: standard
provisioner: microk8s.io/hostpath
EOF
fi
';

echo "# Done. The cluster should be ready for y-stack installation now."
echo "# To get a kubeconfig: multipass exec "$VM_NAME" -- /snap/bin/microk8s.config"
