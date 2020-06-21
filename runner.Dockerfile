FROM ubuntu:20.04@sha256:8bce67040cd0ae39e0beb55bcb976a824d9966d2ac8d2e4bf6119b45505cee64

RUN set -ex; \
  export DEBIAN_FRONTEND=noninteractive; \
  runDeps='ca-certificates curl git jq'; \
  buildDeps=''; \
  apt-get update && apt-get install -y $runDeps $buildDeps --no-install-recommends; \
  \
  echo disabled: apt-get purge -y --auto-remove $buildDeps; \
  rm -rf /var/lib/apt/lists/*; \
  rm -rf /var/log/dpkg.log /var/log/alternatives.log /var/log/apt /root/.gnupg

RUN set -ex; \
  F=$(mktemp); \
  curl -SLs https://dl.k8s.io/v1.17.2/kubernetes-client-linux-amd64.tar.gz \
    | tee $F \
    | tar xzf - --strip-components=3 -C /usr/local/bin/; \
  echo "c5cd8954953ea348318f207c99c9dcb679d73dbaf562ac72660f7dab85616fd45b0f349d49eae9ea1f6aac7cae5bba839bf70f40b8be686d35605ae147339399 $F" \
    | sha512sum -c -; \
  rm $F

ENV YSTACK_HOME=/usr/local/src/ystack
ENV PATH="${PATH}:${YSTACK_HOME}/bin"

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

ENV SKAFFOLD_UPDATE_CHECK=false
COPY bin/y-skaffold /usr/local/src/ystack/bin/
RUN y-skaffold

COPY . /usr/local/src/ystack
WORKDIR /usr/local/src/ystack

RUN echo 'nonroot:x:65532:65534:nonroot:/home/nonroot:/usr/sbin/nologin' >> /etc/passwd && \
  mkdir -p /home/nonroot && touch /home/nonroot/.bash_history && chown -R 65532:65534 /home/nonroot
USER nonroot:nogroup
