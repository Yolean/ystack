

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
