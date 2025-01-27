# syntax=docker.io/docker/dockerfile:1.7.1
FROM --platform=$TARGETPLATFORM ubuntu:24.04@sha256:80dd3c3b9c6cecb9f1667e9290b3bc61b78c2678c02cbdae5f0fea92cc6734ab \
  as base

RUN set -ex; \
  (cd /usr/local/bin; \
    ln -s ../lib/node_modules/npm/bin/npm-cli.js npm; \
    ln -s ../lib/node_modules/corepack/dist/corepack.js corepack; \
  ); \
  \
  export DEBIAN_FRONTEND=noninteractive; \
  runDeps='ca-certificates curl git jq unzip findutils patch xz-utils'; \
  buildDeps='gpg apt-transport-https'; \
  apt-get update && apt-get install -y $runDeps $buildDeps --no-install-recommends; \
  \
  echo "workaround for y-helm failing in github actions due to get.helm.sh SSL error"; \
  curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null; \
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list; \
  apt-get update && apt-get install -y helm --no-install-recommends; \
  apt_helm_version=$(/usr/bin/helm version --template '{{.Version}}'); \
  mkdir -p /usr/local/src/ystack/bin && cp -av /usr/bin/helm /usr/local/src/ystack/bin/y-helm-${apt_helm_version}-bin; \
  ln -s /usr/local/src/ystack/bin/y-helm-${apt_helm_version}-bin /usr/local/src/ystack/bin/helm; \
  \
  apt-get purge -y --auto-remove $buildDeps helm; \
  rm -rf /var/lib/apt/lists/*; \
  rm -rf /var/log/dpkg.log /var/log/alternatives.log /var/log/apt /root/.gnupg

ENV YSTACK_HOME=/usr/local/src/ystack \
  PATH="${PATH}:/usr/local/src/ystack/bin" \
  SKAFFOLD_INSECURE_REGISTRY='builds-registry.ystack.svc.cluster.local,prod-registry.ystack.svc.cluster.local' \
  SKAFFOLD_UPDATE_CHECK=false \
  TURBO_NO_UPDATE_NOTIFIER=1 \
  TURBO_GLOBAL_WARNING_DISABLED=1 \
  DO_NOT_TRACK=1 \
  npm_config_update_notifier=false

FROM --platform=$TARGETPLATFORM node:22.13.1-bookworm-slim@sha256:d6d1b3a6f21a25e43d765816281b4a86e5f1ebf843cfae1b14dd0f1c28257cc7 \
  as node

FROM base as bin

COPY bin/y-bin.runner.yaml \
  bin/y-bin-download \
  bin/y-bin-dependency-download \
  /usr/local/src/ystack/bin/

COPY bin/y-kubectl /usr/local/src/ystack/bin/
RUN y-kubectl version --client=true --output=json

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
