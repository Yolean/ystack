# syntax=docker/dockerfile:1.4
FROM --platform=$TARGETPLATFORM ubuntu:22.04@sha256:0bced47fffa3361afa981854fcabcd4577cd43cebbb808cea2b1f33a3dd7f508 \
  as base

RUN set -ex; \
  (cd /usr/local/bin; \
    ln -s ../lib/node_modules/npm/bin/npm-cli.js npm; \
    ln -s ../lib/node_modules/corepack/dist/corepack.js corepack; \
  ); \
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
  SKAFFOLD_UPDATE_CHECK=false \
  TURBO_NO_UPDATE_NOTIFIER=1 \
  npm_config_update_notifier=false

FROM --platform=$TARGETPLATFORM node:18.17.1-bullseye-slim@sha256:b5846dae07bfe20bd6863c51b3b8745efc7433671bfc5ac46f98f3ae684f5b1f \
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

COPY bin/y-crane /usr/local/src/ystack/bin/
RUN y-crane version

COPY bin/y-yq /usr/local/src/ystack/bin/
RUN y-yq --version

COPY bin/y-skaffold /usr/local/src/ystack/bin/
RUN y-skaffold config set --global collect-metrics false

COPY bin/y-esbuild /usr/local/src/ystack/bin/
RUN y-esbuild --version

COPY bin/y-turbo /usr/local/src/ystack/bin/
RUN y-turbo --version

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
