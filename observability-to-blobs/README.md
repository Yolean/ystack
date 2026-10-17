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

## k8sagent is a base of its own

The cluster agent could have been part of `nodeagent`, as it uses the node agent's image, namespace and Secret.
It is a base of its own because it is another kind of workload: one replica that reads the API server, with its own RBAC (get, list and watch on everything, Secrets included: the agent reads them only with `SECRETS_MODE=scrambled`, which scrambles every value, and the default skips them), and no node access.
A cluster can want one without the other, and each is tuned by its own environment (`SECRETS_MODE`, `CRD_MODE`, `SNAPSHOT_INTERVAL` only for the cluster agent).
The image is pinned once, in `nodeagent-image`, so that the two cannot drift apart.

## What the consumer's overlay brings

The bases hold no bucket and no credentials.

- **A Secret `node-agent-s3`** in namespace `observability`, with `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` of a writer for the bucket. Both agents read it.
- **The location**, which the agents read as `S3_ENDPOINT`, `S3_BUCKET`, `S3_REGION` and `S3_TLS`. The bases set `S3_REGION` and `S3_TLS` to defaults for AWS. An overlay adds a ConfigMap to the container's `envFrom` (and deletes the two defaults, which an `env` entry would otherwise win over), or sets the variables as `env`.
- `CLUSTER_NAME`, the first path segment of the objects, which keeps clusters that share a bucket apart. The bases set `dev`.
- Anything else of the node agent: the cluster's CRI socket path, `STATIC_TARGETS`, and a replacement of `pipeline-extra.yaml` to add filters and outputs.

`from-prometheus-operator/controller` needs [cert-manager](https://cert-manager.io/) for its serving certificate, and the PodMonitor CRD (`crds`, or the cluster's own). It does not create namespace `observability`, so the consumer must; `nodeagent` does.
The controller annotates a pod only when it is created, so converge it before the workloads whose PodMonitors it should translate.

```bash
kubectl apply --server-side -k observability-to-blobs/from-prometheus-operator
```

## Ref

Every base takes o2b at one commit, `c6ea793d9f33438ea7eb319d3a7fd1b07ae2f443`, and the images that CI published for it: `ghcr.io/yolean/observability-nodeagent` and `ghcr.io/yolean/observability-operator-to-annotations`.
To check that no base is left on an older ref:

```bash
grep -rh 'observability-to-blobs/.*ref=' observability-to-blobs | sort -u
```

To move to another commit, change `ref=` in the four `kustomization.yaml` files that have it, and the digests with it (`crane digest <image>:<commit>`). Render each base with `kubectl kustomize` before committing.
The node agent's image is not the one tagged with the ref: its tag, `af3f11ef0e7856e765a04693eb56d4bad4319c73`, is a build of the same `agent/` and `k8sagent/` trees that a consumer has run and validated with these manifests, and the digest is that build's. `crane digest ghcr.io/yolean/observability-nodeagent:c6ea793d9f33438ea7eb319d3a7fd1b07ae2f443` is the build of the ref itself. Moving to it is a change of `nodeagent-image` alone, and rolls the agents.

A consumer pins ystack, too: `https://github.com/Yolean/ystack/observability-to-blobs/nodeagent?ref=<commit>` from a release, or a relative path to a checkout while developing.
