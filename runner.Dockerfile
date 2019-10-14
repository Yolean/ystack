FROM ubuntu:19.10@sha256:a21f154506cc00974f647e13dbba6b7035da35c7669a4bb919515d895221face

RUN set -ex; \
  export DEBIAN_FRONTEND=noninteractive; \
  runDeps='ca-certificates curl'; \
  buildDeps=''; \
  apt-get update && apt-get install -y $runDeps $buildDeps --no-install-recommends; \
  \
  echo disabled: apt-get purge -y --auto-remove $buildDeps; \
  rm -rf /var/lib/apt/lists/*; \
  rm -rf /var/log/dpkg.log /var/log/alternatives.log /var/log/apt /root/.gnupg

RUN set -ex; \
  F=$(mktemp); \
  curl -SLs https://dl.k8s.io/v1.16.1/kubernetes-client-linux-amd64.tar.gz \
    | tee $F \
    | tar xzf - --strip-components=3 -C /usr/local/bin/; \
  echo "e355a74a17d96785b0b217673e67fa0f02daa1939f10d410602ac0a0d061a4db71d727b67f75aa886007dab95dd5c7f8cc38253d291dc4d2504ce673df69fb32 $F" \
    | sha512sum -c -; \
  rm $F

COPY . /usr/local/src/ystack

ENV YSTACK_HOME=/usr/local/src/ystack
ENV PATH="${PATH}:${YSTACK_HOME}/bin"

RUN y-skaffold
