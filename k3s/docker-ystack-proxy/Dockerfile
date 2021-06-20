FROM lachlanevenson/k8s-kubectl:v1.20.7@sha256:7b9dc5efb330fa7605a784b9d69dc7e3944aebd1db92b9fc67654d59a7c5362a as kubectl

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

FROM envoyproxy/envoy:v1.16.2@sha256:8a1d010267ee291bb0e7f12bb24e43b255c771629d70482910bc1f13a56e6b2f

COPY --from=kubectl /usr/local/bin/kubectl /usr/local/bin/kubectl

COPY bin/kubectl-waitretry /usr/local/bin/kubectl-waitretry

COPY --from=kubectl /var/lib/rancher/k3s/server/manifests /var/lib/rancher/k3s/server/manifests

COPY k3s/docker-ystack-proxy/envoy.template.yaml /envoy.template.yaml
COPY k3s/docker-ystack-proxy/entrypoint.sh /usr/local/bin/entrypoint
ENTRYPOINT [ "entrypoint" ]
