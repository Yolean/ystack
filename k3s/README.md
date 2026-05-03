
This structure is the configuration for [y-cluster-converge-ystack](../bin/y-cluster-converge-ystack).

Converge principles:

- List the bases in order.
  Filter out any name that ends with `-disabled`.
- Single pass: apply each base with `kubectl apply -k`.
  `1*` bases use `--server-side=true --force-conflicts` (required for large CRDs).
- Between digit groups (0→1, 1→2, etc.), wait for all deployment rollouts.
- After `1*`, validate that CRDs are registered and served.
- Before `6*`, verify y-kustomize serves real content via
  `curl http://y-kustomize:8944/openapi.yaml` (live spec from y-cluster serve;
  secrets from `3*` and `4*` need time to propagate to the watch).

Each base is applied with `kubectl apply -k` — no label selectors, no multi-pass.

Bases:

- 0*: namespaces + y-kustomize empty secret init (never deleted)
- 1*: Gateway API, CRDs
- 2*: y-kustomize deployment, gateway
- 3*: blobs (real y-kustomize blobs secret)
- 4*: kafka (real y-kustomize kafka secret)
- 5*: monitoring
- 6*: registries, buildkit (depend on y-kustomize HTTP for remote bases)
