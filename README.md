# Registry setup

To facilitate in-cluster container builds y-stack requires a local registry,
or local proxy to a registry.

The requirements, that are captured (kaptured?) in the [kontrakt](./kontrakt) are:
 * Pods can push to `builds.registry.svc.cluster.local`.
 * Containers can use the same registry URLs to start
   - i.e. nodes can pull from these URLs

Example local registry setups:
 * [TriggerMesh](https://github.com/triggermesh/knative-local-registry)
 * [Minikube](https://github.com/kubernetes/minikube/tree/v1.1.1/deploy/addons/registry)
 * [Microk8s](https://github.com/ubuntu/microk8s/blob/1.14/microk8s-resources/actions/registry.yaml) with its [containerd config](https://github.com/ubuntu/microk8s/blob/1.14/microk8s-resources/default-args/containerd-template.toml#L52)
 * The [Kubernetes addon](https://github.com/kubernetes/kubernetes/tree/release-1.9/cluster/addons/registry) that was [deleted](https://github.com/kubernetes/kubernetes/commit/d6918bbbc0402fc81a53479f4b61b836d7c33a29#diff-f3d84c54d8980e52df246570a5c71041) after 1.9.
