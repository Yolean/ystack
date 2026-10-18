# observability-to-blobs

Kustomize bases for [observability-to-blobs](https://github.com/Yolean/observability-to-blobs) (o2b), which ships a cluster's logs, metrics and API objects as objects to S3, and nothing else.
Each base here wraps o2b's own base at one pinned ref and pins the image by digest, so that a consumer takes the pair that was tested together.

| base | what it is | o2b base |
|---|---|---|
| `nodeagent` | the node agent, a DaemonSet in namespace `observability` (the base creates the namespace) | `agent/` |
| `k8sagent` | the cluster agent, one Deployment that uploads every object the API server serves, Events included | `k8sagent/` |
| `from-prometheus-operator` | `crds` and `controller` together | `operator-to-annotations/` |
| `from-prometheus-operator/crds` | the five prometheus-operator CRDs (v1) that shared manifests carry, for a cluster without the operator | `operator-to-annotations/crds` |
| `from-prometheus-operator/controller` | a mutating webhook that translates PodMonitors into the OpenTelemetry scrape annotations the node agent reads | `operator-to-annotations/controller` |
| `nodeagent-image` | a Component with the image pin of the two agents, which share one image | |
| `cluster-name` | a Component that makes the two agents read `CLUSTER_NAME` from the consumer's ConfigMap | |

## k8sagent is a base of its own

The cluster agent could have been part of `nodeagent`, as it uses the node agent's image, namespace and Secret.
It is a base of its own because it is another kind of workload: one replica that reads the API server, with its own RBAC (get, list and watch on everything, Secrets included: the agent reads them only with `SECRETS_MODE=scrambled`, which scrambles every value, and the default skips them), and no node access.
A cluster can want one without the other, and each is tuned by its own environment (`SECRETS_MODE`, `CRD_MODE`, `SNAPSHOT_INTERVAL` only for the cluster agent).
The image is pinned once, in `nodeagent-image`, so that the two cannot drift apart.

## What the consumer's overlay brings

The bases hold no bucket and no credentials.

- **A Secret `node-agent-s3`** in namespace `observability`, with `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` of a writer for the bucket. Both agents read it.
- **The location**, which the agents read as `S3_ENDPOINT`, `S3_BUCKET`, `S3_REGION` and `S3_TLS`. The bases set `S3_REGION` and `S3_TLS` to defaults for AWS. An overlay adds a ConfigMap to the container's `envFrom` (and deletes the two defaults, which an `env` entry would otherwise win over), or sets the variables as `env`.
- **A ConfigMap `observability-cluster`** in namespace `observability`, with key `CLUSTER_NAME`: the first path segment of the objects, which keeps clusters that share a bucket apart, a lowercase name of letters, digits, `-`, `_` and `.`. Both agents read it (`cluster-name`). It has no default: without the ConfigMap or the key the pods stay in `CreateContainerConfigError`, and `kubectl describe pod` names what is missing. Set it only there: an overlay that also sets `CLUSTER_NAME` as an `env` value is refused by the API server, as one env entry cannot have both `value` and `valueFrom`.
- Anything else of the node agent: the cluster's CRI socket path, `STATIC_TARGETS`, and a replacement of `pipeline-extra.yaml` to add filters and outputs.

`from-prometheus-operator/controller` needs [cert-manager](https://cert-manager.io/) for its serving certificate, and the PodMonitor CRD (`crds`, or the cluster's own). It does not create namespace `observability`, so the consumer must; `nodeagent` does.
The controller annotates a pod only when it is created, so converge it before the workloads whose PodMonitors it should translate.

```bash
kubectl apply --server-side -k observability-to-blobs/from-prometheus-operator
```

A consumer's overlay, with the cluster's name and the bucket's location; the Secret comes from wherever the consumer keeps secrets:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- https://github.com/Yolean/ystack/observability-to-blobs/nodeagent?ref=<commit>
configMapGenerator:
- name: observability-cluster
  namespace: observability
  literals:
  - CLUSTER_NAME=my-cluster
patches:
- patch: |
    apiVersion: apps/v1
    kind: DaemonSet
    metadata:
      name: node-agent
      namespace: observability
    spec:
      template:
        spec:
          containers:
          - name: agent
            env:
            - name: S3_ENDPOINT
              value: https://s3.example.net
            - name: S3_BUCKET
              value: my-bucket
```

On k3s the containerd socket is `/run/k3s/containerd/containerd.sock`: the overlay replaces the `cri` volume's `hostPath`, as o2b's `itest/k8s` does.

## Scrape annotations

The node agent scrapes the pods that ask for it by annotation, in o2b's README's "Scrape annotations" forms: `prometheus.io/*`, or the OpenTelemetry keys `io.opentelemetry.discovery.metrics[.<port>]/*`.
An exporter that reports on other objects, as kube-state-metrics does with its own `namespace` and `pod` labels, sets `honor_labels: true` in the OpenTelemetry form's `config`, so that its samples' labels win where rows become series ("honor_labels" there); `prometheus.io/*` has no counterpart.
That is a pod annotation, so no base here carries it: ystack's `monitoring/kube-state-metrics` does.
A PodMonitor endpoint's `honorLabels` reaches the pod through `from-prometheus-operator/controller`.

## Upgrade order

o2b's raw contract may change between releases before 1.0, and the compactor refuses a field it does not know from v0.2.1 on; v0.2.1 adds `honor_labels` to the metrics rows.
A compactor of v0.2.0 or earlier drops such a field without a word, so a cluster whose bucket a compactor reads moves the compactor to at least the agents' release first, then these bases (o2b's README, "What the agent ships").
No base here deploys the compactor.

## Ref

Every base takes o2b at one commit, `1170b7abf704d633315a230c9125b337fe54401a`, the release v0.2.1, and the images that CI published for it, tagged with the commit: `ghcr.io/yolean/observability-nodeagent` and `ghcr.io/yolean/observability-operator-to-annotations`.
To check that no base is left on an older ref:

```bash
grep -rh 'observability-to-blobs/.*ref=' observability-to-blobs | sort -u
```

To move to another commit, change `ref=` in the four `kustomization.yaml` files that have it, and the digests with it in `nodeagent-image` and `from-prometheus-operator/controller` (`crane digest <image>:<commit>`). Render each base with `kubectl kustomize` before committing, and read o2b's README for what the release requires of a consumer and of the upgrade order.

A consumer pins ystack, too: `https://github.com/Yolean/ystack/observability-to-blobs/nodeagent?ref=<commit>` from a release, or a relative path to a checkout while developing.
