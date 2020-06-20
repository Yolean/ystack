FROM rancher/k3s:v1.18.4-k3s1@sha256:2555ed1896512b320c175859a95a5f1d6a2c64b501a84bc45d853a9bd0be0dfd

COPY k3s/docker-image/registries.yaml /etc/rancher/k3s/registries.yaml
# The clusterIP should be predefined
RUN sed -i 's|http://builds-registry.ystack.svc.cluster.local|http://10.43.0.50|' /etc/rancher/k3s/registries.yaml

# Unfortunately /var/lib/rancher/k3s is a VOLUME so this has no effect on server start
# COPY registry/generic /etc/ystack/registry/generic
# COPY k3s /etc/ystack/k3s
# RUN set -ex; \
#   mkdir -p /var/lib/rancher/k3s/server/manifests; \
#   for base in 00-ystack-namespace in-docker-builds-registry; do \
#     kubectl kustomize /etc/ystack/k3s/$base > /var/lib/rancher/k3s/server/manifests/ystack-$base.yaml; \
#   done