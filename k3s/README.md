
This structure is the configuration for [y-cluster-converge-ystack](../bin/y-cluster-converge-ystack).

Converge principles:

- List the bases in order.
  We might invent include and exclude options for this listing later.
  For now only filter out any name that ends with `-disabled`.
- Apply `0*-` bases.
  Should only be namespaces.
  `0*` should _never_ be used with delete (if and when we implement re-converge).
- Apply CRDs (`1*`) explicitly using `--server-side=true --force-conflicts` (required for large CRDs).
  Use kubectl get to validate that applied CRDs are registered.
  <!-- The yolean.se/module-part=crd selector is not yet supported. -->
- Apply with `yolean.se/module-part=config` selector (`2*`+).
- Apply with `yolean.se/module-part=services` selector (`2*`+).
- Apply with `yolean.se/module-part=gateway` selector (`2*`+).
  Render failures during selector phases are tolerated (bases with y-kustomize HTTP resources
  can't render until y-kustomize is up, but they get applied in the full apply step).
- Verify [y-kustomize api](../y-kustomize/openapi/openapi.yaml) endpoints using curl.
  Config secrets are mounted in-place, so no restart is needed — this supports repeated converge.
- Full apply without selector (`2*`+).
  Bases with remote y-kustomize HTTP resources (e.g. 60-builds-registry) render here,
  after y-kustomize compliance is verified.

Each base is rendered inline (`kubectl kustomize | kubectl apply`) — no prerendering or deferred passes.

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
