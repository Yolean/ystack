FROM ubuntu:19.10@sha256:a5193c15d7705bc2be91781355c4932321c06c18914facdd113d5bfcace7f92d

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
  curl -SLs https://dl.k8s.io/v1.16.2/kubernetes-client-linux-amd64.tar.gz \
    | tee $F \
    | tar xzf - --strip-components=3 -C /usr/local/bin/; \
  echo "69bb92c9b16c0286d7401d87cc73b85c88d6f9a17d2cf1748060e44525194b5be860daf7554c4c6319a546c9ff10f2b4df42a27e32d8f95a4052993b17ef57c0 $F" \
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

COPY bin/y-skaffold /usr/local/src/ystack/bin/
RUN y-skaffold

COPY --from=gcr.io/go-containerregistry/github.com/google/go-containerregistry/cmd/crane@sha256:2ebe1fffc23ac887cde2718b46f6133511b089e358bc08baa4de465675a1188f \
  /ko-app/crane /usr/local/bin/crane

COPY . /usr/local/src/ystack
WORKDIR /usr/local/src/ystack

# exists in ubuntu already with uid 65534:
#USER nobody:nogroup
# https://github.com/GoogleContainerTools/distroless/pull/368
# docker run --rm --entrypoint cat gcr.io/distroless/base:debug-nonroot /etc/passwd
RUN groupadd -g 65532 nonroot && \
  useradd --create-home --home-dir /home/nonroot --uid 65532 --gid 65532 -c nonroot -s /usr/sbin/nologin nonroot
USER nonroot:nonroot
