
This structure is the configuration for [y-cluster-converge-ystack](../bin/y-cluster-converge-ystack).

Converge principles:

1. List the bases in order.
   We might invent include and exclude options for this listing later.
   For now only filter out any name that ends with `-disabled`.
2. Render every base (nn-*) to a corresponding multi-item yaml in an ephemeral tmp folder unique to this invocation.
   - Render works as validation
3. Apply `0*-` bases.
   Should only be namespaces.
   `0*` should _never_ be used with delete (if and when we implement re-converge).
4. Apply with `yolean.se/module-part=crd` selector.
   Log what was applied (actually all apply steps can do that, so the apply loop can be reused).
5. Use kubectl get to validate that applied CRDs are registered.
6. Apply with `yolean.se/module-part=config` selector.
7. Apply with `yolean.se/module-part=services` selector.
8. Apply with `yolean.se/module-part=gateway` selector.
   Use curl with short timeout (and retries capped so total time is <60s) to verify [y-kustomize api](./y-kustomize/openapi/openapi.yaml) endpoints retrieved using yq.
9. Apply without selector.

Note that it's optional to use the `module-part` labels.
For example:
- "services" is only necessary for those that gateway resources depend on.
- "config" is only necessary on secrets that y-kustomize depends on.

Bases:

- 0*: namespaces, never deleted
- 1*: Gateway API - anything that's not the responsiblity of each provision script.
- 2*: ystack core (if there is any)
- 3*: blobs
  TODO rename the minio impl, add the `-disabled` suffix.
- 4*: kafka
- 5*: monitoring
- 6*: registries, buildkit
