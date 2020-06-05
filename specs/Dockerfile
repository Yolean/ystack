FROM builds-registry.ystack.svc.cluster.local/yolean/kubernetes-assert/runtime-nodejs:a37053500670cc936b3b9fb05362bea5005ee20c

WORKDIR /usr/src/specs

COPY --chown=nonroot:nogroup package*.json ./

RUN npm ci --ignore-scripts

COPY --chown=nonroot:nogroup . .
