

Y-stack is higly opinionated:
It says "registry" to refer to a Docker registry with a particular setup,
while "knative" refers to an installer that combines Knative modules.
The point with being opinionated is that registry and knative work well together.

The stack supports local developmment using Skaffold with local and remote clusters alike.
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

## Kubectl context management

At Yolean we share kubectl commands that target a specific cluster and namespace.
This is so that when you copy a command from Slack or a readme, you don't accidentally target a prod cluster.

Cluster management is however _outside_ the scope of Y-stack. Instead look at tools like:
 * https://github.com/jonmosco/kube-ps1
 * https://github.com/aluxian/fish-kube-prompt
 * https://github.com/superbrothers/zsh-kubectl-prompt
 * https://github.com/postfinance/kubectl-ctx
 * https://github.com/jordanwilson230/kubectl-plugins#kubectl-switch
 * https://github.com/solsson/bash-kubectl-git/pull/3

Our policy also implies that we need some bot warning against kubectl without `--context` or `--namespace` in Slack,
and likewise some CI tool that enforces kubectl hygiene in markdown.

One more thing: We need to agree on kubectl context names. How do we share those?

## Dependencies

Y-stack doesn't have a CLI, but depends on assorted tooling from the Kubernetes community.
To ease the burden of maintaining a dev stack, there's tooling to keep these binaries updated.
If a requred binary exists in path, a version check is performed.
If not it is downloaded and placed in `$YSTACK_HOME/bin`.


## Hooks

The y-build command is a general purpose util to build a service from its source folder.
Builds are rarely generic though, so it first invokes an executable file `build-pre` in `$YSTACK_HOOKS` if existent.
`$YSTACK_HOOKS` defaults to `$YSTACK_HOME/hooks`.

`y-build-buldkit-host` selects a buildkitd endpoint.

## Namespace

Why do we name the stack namespace with a stage, for example `ystack-dev`?
Still doesn't guard against mistakes, because `kubectl -n ystack-dev delete pod`

## Cluster setup

1. Provision
   - Kubectl access with current (or default) `KUBECONFIG`
   - Current user can configure rbac
   - A default namespace selected (not used yet)
   - Creates namespace `ystack`
   - Set up container runtime to support insecure pull from `builds-registry.ystack.svc.cluster.local`
2. Converge `kubectl apply -k converge/generic/`
3. Forward
   - port-forward the dev stack for local development
   - `sudo -E kubefwd svc -n ystack`

## Tooling

Y-stack is opinionated on Kubernetes devops tooling as well.
We therefore download some CLIs to the aforementioned `PATH` entry.
