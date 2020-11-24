FROM lachlanevenson/k8s-kubectl:v1.18.11@sha256:6bf72a69b1b7748af84eaebc5cb4bdf91d716dbac3d67e23d7c450788066fc5e as kubectl

RUN apk add --no-cache git

COPY . /etc/ystack

# Install the things we need to proxy, but nothing more because big apply chunks are hard to maintain
# This list of bases also exists in ../../bin/y-cluster-provision-k3s-multipass
RUN set -ex; \
  mkdir -p /var/lib/rancher/k3s/server/manifests; \
  for base in \
      00-ystack-namespace \
      10-minio \
      20-builds-registry \
      21-prod-registry \
      30-y-assert-support \
      40-buildkit; do \
    kubectl kustomize /etc/ystack/k3s/$base > /var/lib/rancher/k3s/server/manifests/ystack-$base.yaml; \
  done

FROM envoyproxy/envoy:v1.15.0@sha256:f455fd7b45c2fe5d2862e19a3858284bbffc9c72359e0012641b59859d5c68db

COPY --from=kubectl /usr/local/bin/kubectl /usr/local/bin/kubectl

COPY bin/kubectl-waitretry /usr/local/bin/kubectl-waitretry

COPY --from=kubectl /var/lib/rancher/k3s/server/manifests /var/lib/rancher/k3s/server/manifests

COPY k3s/docker-ystack-proxy/envoy.template.yaml /envoy.template.yaml
COPY k3s/docker-ystack-proxy/entrypoint.sh /usr/local/bin/entrypoint
ENTRYPOINT [ "entrypoint" ]
