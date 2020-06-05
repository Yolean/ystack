FROM builds-registry.ystack.svc.cluster.local/yolean/kubernetes-assert/runtime-nodejs:594d9886eca5175b90dcd96584578b8a42d5fc26

WORKDIR /usr/src/specs

COPY --chown=nonroot:nogroup package*.json ./

RUN npm ci --ignore-scripts

COPY --chown=nonroot:nogroup . .
