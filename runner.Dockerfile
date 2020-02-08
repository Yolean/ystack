FROM ubuntu:20.04@sha256:7922db6447e9d1470e3bf821e8ff228d70c3593e822e980c58bf9185821ac645

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

ENV SKAFFOLD_UPDATE_CHECK=false
COPY bin/y-skaffold /usr/local/src/ystack/bin/
RUN y-skaffold

COPY --from=gcr.io/go-containerregistry/crane:aec8da010de25d23759d972d7896629d6ae897d8 \
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
