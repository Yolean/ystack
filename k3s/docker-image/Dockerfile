FROM rancher/k3s:v1.20.7-k3s1@sha256:e952613fe293457e25c642c2e97ae8f1294b97694093fd3ca232371b4b4a3d10

COPY k3s/docker-image/registries.yaml /etc/rancher/k3s/registries.yaml
# The clusterIP should be predefined
RUN sed -i 's|http://builds-registry.ystack.svc.cluster.local|http://10.43.0.50|' /etc/rancher/k3s/registries.yaml
RUN sed -i 's|http://prod-registry.ystack.svc.cluster.local|http://10.43.0.51|' /etc/rancher/k3s/registries.yaml

# Unfortunately /var/lib/rancher/k3s is a VOLUME so this has no effect on server start
# COPY registry/generic /etc/ystack/registry/generic
# COPY k3s /etc/ystack/k3s
# RUN set -ex; \
#   mkdir -p /var/lib/rancher/k3s/server/manifests; \
#   for base in 00-ystack-namespace in-docker-builds-registry; do \
#     kubectl kustomize /etc/ystack/k3s/$base > /var/lib/rancher/k3s/server/manifests/ystack-$base.yaml; \
#   done
