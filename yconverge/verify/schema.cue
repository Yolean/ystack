package verify

// A convergence step: apply a kustomize base, then verify.
// The yconverge.cue file must be next to a kustomization.yaml.
// The kustomization path is implicit from the file location.
#Step: {
	// Checks that must pass after apply.
	// Empty list means the step is ready immediately after apply.
	checks: [...#Check]
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
