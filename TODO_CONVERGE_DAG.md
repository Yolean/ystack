# Converge DAG: CUE-based cluster convergence

## Problem

Dependencies between backends and modules are implicit in script ordering
(MANUAL_STEPS_FOR_NEW_SITES, y-site-upgrade, y-cluster-converge-dev).
Adding or reordering a module means editing a bash script.

## Design

Every kustomize base that can be applied with `kubectl yconverge -k`
is a **step**. Each step declares its readiness via **checks**.
Dependencies between steps are expressed as **CUE imports** —
importing another step's package makes it a precondition.

The dependency graph is the CUE import graph.
A `cue cmd converge` walks it in topological order.

## ystack provides

Schema in `cue/converge/schema.cue`:

```cue
package converge

// A convergence step: apply a kustomize base, then verify.
#Step: {
    // Path to kustomize directory, relative to repo root.
    kustomization: string
    // Namespace override. If unset, kustomization must set it.
    namespace?: string
    // Checks that must pass after apply (and that downstream steps
    // use as preconditions by importing this package).
    // Empty list means no checks — the step is ready after apply.
    checks: [...#Check]
}

// Check is a discriminated union. Each variant maps to a kubectl
// subcommand that manages its own timeout and output.
#Check: #Wait | #Rollout | #Exec

// Thin wrapper around kubectl wait.
// Timeout and output are managed by kubectl.
#Wait: {
    kind:        "wait"
    resource:    string   // e.g. "pod/redpanda-0" or "job/setup-topic"
    for:         string   // e.g. "condition=Ready" or "condition=Complete"
    namespace?:  string
    timeout:     *"60s" | string
    description: *"" | string
}

// Thin wrapper around kubectl rollout status.
// Timeout and output are managed by kubectl.
#Rollout: {
    kind:        "rollout"
    resource:    string   // e.g. "deploy/gateway-v4" or "statefulset/redpanda"
    namespace?:  string
    timeout:     *"60s" | string
    description: *"" | string
}

// Arbitrary command for checks that don't map to kubectl builtins.
// The engine retries until timeout.
#Exec: {
    kind:        "exec"
    command:     string
    timeout:     *"60s" | string
    description: string
}
```

## Validation

`cue vet` validates that every `y-k8s.cue` file conforms to the schema.
This runs without a cluster — it's a static check on the declarations.

```
y-cue vet ./...
```

This catches: missing required fields, wrong check types, invalid
timeout formats, typos in field names (CUE is closed by default —
unknown fields are errors).

CI can run `cue vet` to ensure all modules comply before merge.

## Engine

The engine in `cue/converge/converge_tool.cue` translates checks
to kubectl commands:

```cue
// #Wait  -> kubectl wait --for=$for --timeout=$timeout $resource [-n $namespace]
// #Rollout -> kubectl rollout status --timeout=$timeout $resource [-n $namespace]
// #Exec  -> retry with $timeout: sh -c $command
```

`kubectl wait` and `kubectl rollout status` handle their own polling
and timeout — the engine just propagates the timeout value and
passes through stdout/stderr.

For `#Exec` checks the engine manages the retry loop.

`kubectl-yconverge` handles the apply modes (create, replace,
serverside, serverside-force, regular).
The engine does not need to know about apply strategies.

## Modules provide

Each module has a `y-k8s.cue` that declares its step and checks.
A module with no checks is valid — it just declares the kustomization.

Example `kafka-v3/y-k8s.cue` (backend with rollout check):

```cue
package kafka_v3

import "yolean.se/ystack/cue/converge"

step: converge.#Step & {
    kustomization: "cluster-local/kafka-v3"
    checks: [
        {kind: "rollout", resource: "statefulset/redpanda", namespace: "kafka", timeout: "120s"},
        {kind: "exec", command: "kubectl exec -n kafka redpanda-0 -- rpk cluster info", description: "redpanda cluster healthy"},
    ]
}
```

Example `cluster-local/mysql/y-k8s.cue` (backend, no checks needed):

```cue
package mysql

import "yolean.se/ystack/cue/converge"

step: converge.#Step & {
    kustomization: "cluster-local/mysql"
    checks: []
}
```

Example `gateway-v4/y-k8s.cue` (module with dependencies):

```cue
package gateway_v4

import (
    "yolean.se/ystack/cue/converge"
    "yolean.se/checkit/cluster-local/kafka-v3"
    "yolean.se/checkit/keycloak-v3"
)

// Importing kafka_v3 and keycloak_v3 makes their checks
// preconditions for this step. The engine ensures they
// converge and pass before applying gateway-v4.

step: converge.#Step & {
    kustomization: "gateway-v4/site-apply-namespaced"
    checks: [
        {kind: "rollout", resource: "deploy/gateway-v4", namespace: "dev"},
        {kind: "wait", resource: "job/setup-topic-gateway-v4-userstate", namespace: "dev", for: "condition=Complete"},
    ]
}
```

## Dependency resolution

The engine collects all `y-k8s.cue` files, inspects their imports,
and builds a topological sort. A step runs only after all imported
steps have converged and their checks pass.

Import cycles are a CUE compile error — no runtime cycle detection needed.

## Namespace binding

`y-site-generate` determines which modules a site needs and which
namespace they target. The CUE engine receives `--context=` and
site name as inputs. Namespace is either set in the kustomization
or passed as a CUE value that templates into check commands.

## Convergence is cheap

`kubectl yconverge -k` is idempotent. Re-running a fully converged
step is a no-op (unchanged resources) followed by passing checks.
This means:

- No "has this been applied" state tracking
- Re-running after a failure retries only what's needed
- Checks serve double duty: post-apply verification AND
  precondition for downstream steps

## CLI surface

```
y-cue cmd converge --context=local dev              # full site
y-cue cmd converge --context=local dev gateway-v4    # one module + deps
y-cue cmd check --context=local dev                  # checks only, no apply
y-cue vet ./...                                      # validate all y-k8s.cue
```

## Migration path

1. Add schema to ystack `cue/converge/`
2. Write `y-k8s.cue` for ystack backends (kafka, blobs, builds-registry)
3. Write `y-k8s.cue` for checkit backends (mysql, keycloak-v3)
4. Write `y-k8s.cue` for a few site modules (gateway-v4, events-v1)
5. `cue cmd converge --context=local dev` replaces
   `y-cluster-provision-first-site dev` for local clusters
6. Extend to `y-site-upgrade` by adding upgrade-specific checks
7. Extend to non-local clusters by parameterizing context and namespace
