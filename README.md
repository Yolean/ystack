
# Y-stack

Y-stack is a micro-PaaS(?) with the following goals:

 - Allow every developer to experiment with architecture on a _cluster level_
 - Make moitoring and alerts a first class tool in coding
 - Make Kubernetes patterns like sidecars and operators an intergral part of design
 - Support event-driven microservices patterns

## Why

Y-stack is higly opinionated:
It says "registry" to refer to a Docker registry with a particular setup,
while "knative" refers to an installer that combines Knative modules.
The point with being opinionated is that registry and knative work well together.

The stack supports local development ("inner development loop") using
[Skaffold](https://skaffold.dev/)
with local and remote clusters alike.
Image builds during development are in-cluster:
Many dev setups transfer container images but we transfer the build context.
We see builds as temporary and per-cluster,
though they upon different kinds of verification can be pushed to a productiono registry.
Build contexts are small and there's no need to git push to trigger a build.

Y-stack should be independent of cluster vendor,
but we provide some utilities like [microk8s-multipass.sh](./microk8s-multipass.sh) to automate cluster creation.
Note that these scripts don't actually apply anything.
Actually installing y-stack is done through `kubectl apply -k [path(s) in this repo]`.

## TLS certificate for https

A crucial part of modern development is to access your stack using `https://`.
For that you need a valid SSL certificate.
If your cluster has a public IP we assume that you can get real valid certificats,
through for example LetsEncrypt.

If your cluster has a local IP you'll probably want something like [mkcert](https://github.com/FiloSottile/mkcert).
It needs to run locally, so y-stack can't automate much, but some assistance is provided in the form of:
 - A Kustomize base for ingress at [ingress-tls-local](./ingress-tls-local/) which as base for actual ingress resources helps with the transfer of a local cert to in-cluster Ingress.
 - A utility [tls-local.sh](./tls-local.sh) to (re)generate certs for all `host:` entries in any ingress resource.

Unless you have a local DNS that gets updated with your ingress entries,
you'll probably also want to update your /etc/hosts file.
For that we use https://github.com/solsson/k8s-ingress-hosts/releases

## Installation

Add `YSTACK_HOME` env poiting to the root of y-stack, and `$YSTACK_HOME/bin` to path.

## Dependencies

Y-stack doesn't have a CLI, but depends on assorted tooling from the Kubernetes community.
To ease the burden of maintaining a dev stack, there's tooling to keep these binaries updated.
If a requred binary exists in path, a version check is performed.
If not it is downloaded and placed in `$YSTACK_HOME/bin`.

## Namespace

Why do we name the stack namespace with a stage, for example `ystack-dev`?
Still doesn't guard against mistakes, because `kubectl -n ystack-dev delete pod`

## Cluster setup

1. Provision
   - Look for [bin](./bin)s named `y-cluster-provision-*`
   - ... but note that all of them are hacks that you'll probably need to understand
   - Provision rougly means setting up a new cluster for:
     - Kubectl access with current (or default) `KUBECONFIG`
     - Current user can configure rbac
     - A default namespace selected (not used yet)
     - Creates namespace `ystack`
     - Set up container runtime to support insecure pull from `builds-registry.ystack.svc.cluster.local`
   - After provision the cluster should be ready to run Y-stack coponents. Unlike scripts, paths that support `apply -k` should be declarative resource config that you can re-apply and extend.
2. Converge `kubectl apply -k converge-generic/`
   - The `converge-generic` kustomization sets `namespace: ystack`,
     but individual features only set namespace if thery have configuration that depend on a fixed namespace
3. Forward
   - port-forward the dev stack for local development
   - `y-kubefwd svc -n ystack`
4. Test "inner development loop"
   - Check that CLIs are ok using `y-buildctl` and `y-skaffold`
   - In `./examples/basic-dev-inner-loop/` run `skaffold dev`

## Tooling

Y-stack is opinionated on Kubernetes devops tooling as well.
We therefore download some CLIs to the aforementioned `PATH` entry.

## CI test suite

```
docker volume rm ystack_admin 2> /dev/null || true
./test.sh
```

## Development

```
compose='docker-compose -f docker-compose.test.yml -f docker-compose.dev-overrides.yml'
$compose down \
  ;docker volume rm ystack_admin ystack_k3s-server 2>/dev/null || true
$compose up cleanup
$compose up --build -d server
$compose up --build -d agent1
$compose up --build -d ystack-proxy
y-kubie ctx -f ./devcluster/.kube/kubeconfig.yaml
```

To add monitoring support run `y-cluster-assert-install`.

For [dev loops](./examples/) and `y-assert` the docker stack replaces `y-kubefwd` (hard to use in CI)
with container ports.
You need `cat /etc/hosts | grep 127.0.0 | grep cluster.local` to have something like:
```
127.0.0.1	builds-registry.ystack.svc.cluster.local
127.0.0.1	buildkitd.ystack.svc.cluster.local
127.0.0.1	monitoring.ystack.svc.cluster.local
```

Test using:
```
curl http://builds-registry.ystack.svc.cluster.local/v2/
curl http://monitoring.ystack.svc.cluster.local:9090/api/v1/alertmanagers | jq '.data.activeAlertmanagers[0]'
curl http://monitoring.ystack.svc.cluster.local:9093/api/v2/status
```

Start a dev loop for actual asserts using `cd specs; y-skaffold --cache-artifacts=false dev` and start editing specs/*.spec.js.
