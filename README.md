# Registry setup

To facilitate in-cluster container builds y-stack requires a local registry,
or local proxy to a registry.

The requirements, that are captured (kaptured?) in the [kontrakt](./kontrakt) are:
 1. Pods can push to `builds.registry.svc.cluster.local`.
 2. Containers can use the same registry URLs to start
   - i.e. nodes can pull from these URLs

Example local registry setups:
 * [TriggerMesh](https://github.com/triggermesh/knative-local-registry)
 * [Minikube](https://github.com/kubernetes/minikube/tree/v1.1.1/deploy/addons/registry)
 * [Microk8s](https://github.com/ubuntu/microk8s/blob/1.14/microk8s-resources/actions/registry.yaml) with its [containerd config](https://github.com/ubuntu/microk8s/blob/1.14/microk8s-resources/default-args/containerd-template.toml#L52)
 * The [Kubernetes addon](https://github.com/kubernetes/kubernetes/tree/release-1.9/cluster/addons/registry) that was [deleted](https://github.com/kubernetes/kubernetes/commit/d6918bbbc0402fc81a53479f4b61b836d7c33a29#diff-f3d84c54d8980e52df246570a5c71041) after 1.9.


### microk8s

We don't use the registry addon that comes with microk8s because it doesn't meet requirement `2`.

There are two known paths to a working setup, both requiring containerd [restart](https://microk8s.io/docs/working):

Either `kubectl -n registry apply -k generic-tls && kubectl apply -k hosts-update` and then make containerd trust the CA:

```
microk8s.kubectl certificate approve registry-tls   # see logs for the registry-cert-cluster-ca job
ln -s /var/snap/microk8s/current/certs/ca.crt /usr/local/share/ca-certificates/microk8s-local-ca.crt
update-ca-certificates
microk8s.stop
microk8s.start
```

Or `kubectl -n registry apply -k generic` and then patch containerd config to add the registry, for example:

```
SERVICE_IP=$(microk8s.kubectl -n registry get service builds -o=jsonpath='{.spec.clusterIP}')
sed -i 's|      \[plugins.cri.registry.mirrors\]|      [plugins.cri.registry.mirrors]\
        [plugins.cri.registry.mirrors."builds.registry.svc.cluster.local"]\
          endpoint = ["'$SERVICE_IP':80"]|'\
  /var/snap/microk8s/current/args/containerd.toml
microk8s.stop
microk8s.start
```

Restarts could possibly be avoided for the SSL approach after https://github.com/containerd/containerd/issues/3071.
