
This structure is the configuration for [y-cluster-converge-ystack](../bin/y-cluster-converge-ystack).

Converge principles:

1. List the bases in order.
   We might invent include and exclude options for this listing later.
   For now only filter out any name that ends with `-disabled`.
2. Render every base (nn-*) to a corresponding multi-item yaml in an ephemeral tmp folder unique to this invocation.
   - Render works as validation.
   - Bases that reference y-kustomize HTTP resources can't be rendered until step 9.
     These are deferred and rendered just before their apply in step 10.
3. Apply `0*-` bases.
   Should only be namespaces.
   `0*` should _never_ be used with delete (if and when we implement re-converge).
4. Apply CRDs explicitly using `--server-side=true --force-conflicts` (required for large CRDs).
   Use kubectl get to validate that applied CRDs are registered.
   <!-- The yolean.se/module-part=crd selector is not yet supported. -->
5. Apply with `yolean.se/module-part=config` selector.
6. Apply with `yolean.se/module-part=services` selector.
7. Apply with `yolean.se/module-part=gateway` selector.
8. Restart y-kustomize to pick up config changes from step 5.
   Wait for rollout, then verify [y-kustomize api](../y-kustomize/openapi/openapi.yaml) endpoints using curl.
9. Apply without selector.
10. Render and apply deferred bases (those depending on y-kustomize HTTP resources).

Log what was applied (all apply steps can reuse the same apply loop).

Note that it's optional to use the `module-part` labels.
A design goal is to reduce the number of bases by using selectors
to apply resources from the same base at different phases.
For example:
- "services" is only necessary for those that gateway resources depend on.
- "config" is only necessary on secrets that y-kustomize depends on.

Bases:

- 0*: namespaces, never deleted
- 1*: Gateway API, CRDs
- 2*: ystack core (y-kustomize, gateway)
- 3*: blobs
- 4*: kafka
- 5*: monitoring
- 6*: registries, buildkit
