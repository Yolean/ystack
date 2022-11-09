# syntax=docker/dockerfile:1.4
FROM --platform=$TARGETPLATFORM ubuntu:22.04@sha256:4b1d0c4a2d2aaf63b37111f34eb9fa89fa1bf53dd6e4ca954d47caebca4005c2 \
  as base

RUN set -ex; \
  (cd /usr/local/bin; ln -s ../lib/node_modules/npm/bin/npm-cli.js npm); \
  \
  export DEBIAN_FRONTEND=noninteractive; \
  runDeps='ca-certificates curl git jq unzip findutils patch'; \
  buildDeps=''; \
  apt-get update && apt-get install -y $runDeps $buildDeps --no-install-recommends; \
  \
  echo disabled: apt-get purge -y --auto-remove $buildDeps; \
  rm -rf /var/lib/apt/lists/*; \
  rm -rf /var/log/dpkg.log /var/log/alternatives.log /var/log/apt /root/.gnupg

ENV YSTACK_HOME=/usr/local/src/ystack \
  PATH="${PATH}:/usr/local/src/ystack/bin" \
  SKAFFOLD_INSECURE_REGISTRY='builds-registry.ystack.svc.cluster.local,prod-registry.ystack.svc.cluster.local' \
  SKAFFOLD_UPDATE_CHECK=false

FROM --platform=$TARGETPLATFORM node:18.12.1-bullseye-slim@sha256:78e6da5da446d42872eb5c21bb651e478b01613475b321ce9e25e392dd876fff \
  as node

FROM base as bin

COPY bin/y-bin.yaml \
  bin/y-bin-download \
  bin/y-bin-dependency-download \
  /usr/local/src/ystack/bin/

COPY bin/y-kubectl /usr/local/src/ystack/bin/
RUN y-kubectl version --client=true

COPY bin/y-kustomize /usr/local/src/ystack/bin/
RUN y-kustomize version

COPY bin/y-helm /usr/local/src/ystack/bin/
RUN y-helm version --client=true

COPY bin/y-buildctl /usr/local/src/ystack/bin/
RUN y-buildctl --version

COPY bin/y-container-structure-test /usr/local/src/ystack/bin/
RUN y-container-structure-test version

COPY bin/y-crane /usr/local/src/ystack/bin/
RUN y-crane version

COPY bin/y-yq /usr/local/src/ystack/bin/
RUN y-yq --version

COPY bin/y-skaffold /usr/local/src/ystack/bin/
RUN y-skaffold config set --global collect-metrics false

COPY bin/y-esbuild /usr/local/src/ystack/bin/
RUN y-esbuild --version

RUN y-bin-download /usr/local/src/ystack/bin/y-bin.yaml kpt
RUN y-bin-download /usr/local/src/ystack/bin/y-bin.yaml cue

FROM --platform=$TARGETPLATFORM base

COPY --from=node --link /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=node --link /usr/local/bin/node /usr/local/bin/

COPY --from=bin /usr/local/src/ystack/bin /usr/local/src/ystack/bin

COPY . /usr/local/src/ystack
WORKDIR /usr/local/src/ystack

RUN echo 'nonroot:x:65532:65534:nonroot:/home/nonroot:/usr/sbin/nologin' >> /etc/passwd && \
  mkdir -p /home/nonroot && touch /home/nonroot/.bash_history && chown -R 65532:65534 /home/nonroot && \
  chown nonroot /usr/local/src/ystack/bin /usr/local/lib/node_modules && \
  ln -s /home/nonroot/.skaffold /root/.skaffold
USER nonroot:nogroup

RUN y-skaffold config set --global collect-metrics false
