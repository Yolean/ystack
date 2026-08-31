
This structure is the configuration for [y-cluster-converge-ystack](../bin/y-cluster-converge-ystack).

Converge principles:

- List the bases in order.
  Filter out any name that ends with `-disabled`.
- Single pass: apply each base with `kubectl apply -k`.
  `1*` bases use `--server-side=true --force-conflicts` (required for large CRDs).
- Between digit groups (0→1, 1→2, etc.), wait for all deployment rollouts.
- After `1*`, validate that CRDs are registered and served.

Each base is applied with `kubectl apply -k` — no label selectors, no multi-pass.

Bases:

- 0*: namespaces
- 1*: Gateway API, CRDs, buckety-controller (operator + Buckety/BucketyAccess CRDs)
- 2*: gateway
- 3*: blobs (versitygw)
- 4*: kafka
- 5*: monitoring
- 6*: registries, buildkit

Per-resource backend provisioning (Kafka topics, S3 buckets) is
authored as `Buckety` + `BucketyAccess` resources consumed by the
`buckety-controller` Deployment in `1*`. See the consumer
kustomizations under `registry/builds-{bucket,topic}/` and
`kafka/validate-topic/`.
