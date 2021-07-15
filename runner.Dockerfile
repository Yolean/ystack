FROM node:16.5.0-buster-slim@sha256:610ade6f0702b7355a045d7df4e53f78fded0060c5e765f2d5267b1a613465e8 as node

FROM ubuntu:20.04@sha256:aba80b77e27148d99c034a987e7da3a287ed455390352663418c0f2ed40417fe

COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=node /usr/local/bin/node /usr/local/bin/
RUN cd /usr/local/bin && ln -s ../lib/node_modules/npm/bin/npm-cli.js npm

COPY lib/package* /usr/local/lib/node_modules/@yolean/ystack/
RUN cd /usr/local/lib/node_modules/@yolean/ystack && npm ci --ignore-scripts
RUN for B in \
  tsc ts-node \
  jest ts-jest \
  rollup \
  ; do ln -s -v /usr/local/lib/node_modules/@yolean/ystack/node_modules/.bin/$B /usr/local/bin/$B; done

RUN set -ex; \
  export DEBIAN_FRONTEND=noninteractive; \
  runDeps='ca-certificates curl git jq unzip findutils'; \
  buildDeps=''; \
  apt-get update && apt-get install -y $runDeps $buildDeps --no-install-recommends; \
  \
  echo disabled: apt-get purge -y --auto-remove $buildDeps; \
  rm -rf /var/lib/apt/lists/*; \
  rm -rf /var/log/dpkg.log /var/log/alternatives.log /var/log/apt /root/.gnupg

ENV YSTACK_HOME=/usr/local/src/ystack
ENV PATH="${PATH}:${YSTACK_HOME}/bin"
ENV SKAFFOLD_INSECURE_REGISTRY='builds-registry.ystack.svc.cluster.local,prod-registry.ystack.svc.cluster.local'

COPY bin/y-bin-dependency-download /usr/local/src/ystack/bin/

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

ENV SKAFFOLD_UPDATE_CHECK=false
COPY bin/y-skaffold /usr/local/src/ystack/bin/
RUN y-skaffold config set --global collect-metrics false

COPY . /usr/local/src/ystack
WORKDIR /usr/local/src/ystack

RUN echo 'nonroot:x:65532:65534:nonroot:/home/nonroot:/usr/sbin/nologin' >> /etc/passwd && \
  mkdir -p /home/nonroot && touch /home/nonroot/.bash_history && chown -R 65532:65534 /home/nonroot
USER nonroot:nogroup

RUN y-skaffold config set --global collect-metrics false
