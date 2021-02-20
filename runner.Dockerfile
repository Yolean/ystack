FROM yolean/node:504a22ce0db84d7de594a38dc18a60dc82fa30de@sha256:afa0d518bcbf0c276147e02240ccc69f389848762790456d301f314d2beb3f31 as yolean-node

FROM ubuntu:20.04@sha256:703218c0465075f4425e58fac086e09e1de5c340b12976ab9eb8ad26615c3715

COPY --from=yolean-node /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=yolean-node /usr/local/bin/node /usr/local/bin/
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

RUN set -e; \
  F=$(mktemp); \
  curl -SLs https://dl.k8s.io/v1.20.4/kubernetes-client-linux-amd64.tar.gz \
    | tee $F \
    | tar xzf - --strip-components=3 -C /usr/local/bin/; \
  echo "daf1ec0cbd14885170a51d2a09bf652bfaa4d26925c1b4babdc427d2a2903b1a295403320229cde2b415fee65a5af22671afa926f184cf198df7f17a27f19394 $F" \
    | sha512sum -c -; \
  rm $F

ENV YSTACK_HOME=/usr/local/src/ystack
ENV PATH="${PATH}:${YSTACK_HOME}/bin"
ENV SKAFFOLD_INSECURE_REGISTRY='builds-registry.ystack.svc.cluster.local,prod-registry.ystack.svc.cluster.local'

COPY bin/y-bin-dependency-download /usr/local/src/ystack/bin/

COPY bin/y-kustomize /usr/local/src/ystack/bin/
RUN y-kustomize

COPY bin/y-helm /usr/local/src/ystack/bin/
RUN y-helm

COPY bin/y-buildctl /usr/local/src/ystack/bin/
RUN y-buildctl

COPY bin/y-container-structure-test /usr/local/src/ystack/bin/
RUN y-container-structure-test

COPY bin/y-crane /usr/local/src/ystack/bin/
RUN y-crane

COPY bin/y-deno /usr/local/src/ystack/bin/
RUN y-deno -V

ENV SKAFFOLD_UPDATE_CHECK=false
COPY bin/y-skaffold /usr/local/src/ystack/bin/
RUN y-skaffold

COPY . /usr/local/src/ystack
WORKDIR /usr/local/src/ystack

RUN echo 'nonroot:x:65532:65534:nonroot:/home/nonroot:/usr/sbin/nologin' >> /etc/passwd && \
  mkdir -p /home/nonroot && touch /home/nonroot/.bash_history && chown -R 65532:65534 /home/nonroot
USER nonroot:nogroup
