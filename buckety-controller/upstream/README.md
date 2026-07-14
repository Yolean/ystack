# buckety-controller upstream (vendored)

Source: https://github.com/Yolean/buckety-controller
Ref: `ccfb662` on branch `secret-safety-and-events` (YoleanAgents
fork), pre-v0.1.0. The controller image is pinned to the
per-commit CI tag `ghcr.io/yolean/buckety-controller:20260710T113351Z`
(built by the agents-fork e2e workflow for this commit).

Copied verbatim from upstream's `deploy/kustomize/crd/` and
`deploy/kustomize/controller/`, with one local edit: the
`webhook.yaml` ValidatingWebhookConfiguration is **not vendored**
because ystack's acceptance cluster does not run cert-manager and
the upstream webhook config requires it for CA-bundle injection.
The corresponding line in `controller/kustomization.yaml` is
removed.

Consequence: admission-time parameter validation does not fire on
this overlay. The controller's reconcile-time `ValidateParameters`
still runs; bad parameters surface as `Failed` or `ParameterDrift`
conditions on the resource rather than as an `kubectl apply`
rejection. This is a known PoC trade-off; if buckety-controller
ships a cert-manager-less webhook bootstrap path, re-vendor the
webhook and remove this README note.

To refresh, copy the same eight files from a newer upstream tag
or commit. The release base path
(`deploy/kustomize/release/`) will replace this when v0.1.0 ships.
