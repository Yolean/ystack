package converge

// A convergence step: apply a kustomize base, then verify.
// The yconverge.cue file must be next to a kustomization.yaml.
// The kustomization path is implicit from the file location.
#Step: {
	// Checks that must pass after apply.
	// Empty list means the step is ready immediately after apply.
	checks: [...#Check]
	// True after apply + checks complete successfully.
	// Downstream steps that import this package gate on this value.
	// Set by the engine, not by user CUE files.
	up: *false | bool
	// Namespace derived by the engine from:
	//   1. -n CLI arg to kubectl-yconverge
	//   2. kustomization.yaml namespace: field
	//   3. kubectl context default namespace
	// Used as default for #Wait/#Rollout checks that omit namespace.
	// Set by the engine, not by user CUE files.
	namespaceGuess: *"" | string
}

// Check is a discriminated union. Each variant maps to a kubectl
// subcommand that manages its own timeout and output.
#Check: #Wait | #Rollout | #Exec

// Thin wrapper around kubectl wait.
// Timeout and output are managed by kubectl.
#Wait: {
	kind:        "wait"
	resource:    string
	for:         string
	namespace?:  string
	timeout:     *"60s" | string
	description: *"" | string
}

// Thin wrapper around kubectl rollout status.
// Timeout and output are managed by kubectl.
#Rollout: {
	kind:        "rollout"
	resource:    string
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
