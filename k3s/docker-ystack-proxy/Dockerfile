FROM lachlanevenson/k8s-kubectl:v1.18.3@sha256:495f41912554fde10e41ac54e8df6fdbd0e859e893a4cab61c9224b296f3454d as kubectl

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

FROM envoyproxy/envoy:v1.14.1@sha256:ccaf9e0135bf498fb8396ad49defd7f8567bf706411d9a707efb3978fb842c89

COPY --from=kubectl /usr/local/bin/kubectl /usr/local/bin/kubectl

COPY bin/kubectl-waitretry /usr/local/bin/kubectl-waitretry

COPY --from=kubectl /var/lib/rancher/k3s/server/manifests /var/lib/rancher/k3s/server/manifests

COPY k3s/docker-ystack-proxy/envoy.template.yaml /envoy.template.yaml
COPY k3s/docker-ystack-proxy/entrypoint.sh /usr/local/bin/entrypoint
ENTRYPOINT [ "entrypoint" ]
