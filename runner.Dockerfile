FROM yolean/node:76722e95089e2d8a774ef98721dbd212520eae3c@sha256:4ae69b8821a386e843a6ff292cdf1ee9d9c40384c220556b86efb9314fed226d as yolean-node

FROM ubuntu:20.04@sha256:c95a8e48bf88e9849f3e0f723d9f49fa12c5a00cfc6e60d2bc99d87555295e4c

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
  curl -SLs https://dl.k8s.io/v1.17.16/kubernetes-client-linux-amd64.tar.gz \
    | tee $F \
    | tar xzf - --strip-components=3 -C /usr/local/bin/; \
  echo "5b4fee0702ea7952f5eadf0af46ec0b2bc14fbb3d8777fb745e8c9a3296438d36d994c5753bfc33f886909e2ca7bba5277746c32d50f6a62fb6167fd85eb7f01 $F" \
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
