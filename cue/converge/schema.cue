package converge

// A convergence step: apply a kustomize base, then verify.
#Step: {
	// Path to kustomize directory, relative to repo root.
	kustomization: string
	// Namespace this step targets. Used for filtering (--exclude-namespace).
	namespace?: string
	// Set to false to disable this step (e.g. alternative implementations).
	enabled: *true | bool
	// One-shot mutations that run after apply (not retried).
	actions: [...#Action]
	// Precondition checks from dependencies. Modules populate this
	// from their imported dependencies' checks.
	prechecks: [...#Check]
	// Checks that must pass after apply. Downstream steps that import
	// this package use these as preconditions.
	// Empty list means the step is ready immediately after apply.
	checks: [...#Check]
	// True after apply + actions + checks complete successfully.
	// Downstream steps reference this to express dependencies.
	// Default false; set by the engine at runtime.
	up: *false | bool
}

// Check is a discriminated union. Each variant maps to a kubectl
// subcommand that manages its own timeout and output.
#Check: #Wait | #Rollout | #Exec

// Thin wrapper around kubectl wait.
// Timeout and output are managed by kubectl.
#Wait: {
	kind:        "wait"
	resource:    string // e.g. "pod/redpanda-0" or "crd/gateways.gateway.networking.k8s.io"
	for:         string // e.g. "condition=Ready" or "condition=Established"
	namespace?:  string
	timeout:     *"60s" | string
	description: *"" | string
}

// Thin wrapper around kubectl rollout status.
// Timeout and output are managed by kubectl.
#Rollout: {
	kind:        "rollout"
	resource:    string // e.g. "deploy/y-kustomize" or "statefulset/redpanda"
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

// An imperative action that runs once after apply.
// Unlike checks, actions are not retried -- they either succeed or fail.
#Action: {
	kind:        "action"
	command:     string
	description: string
}
