package example_replace

import "yolean.se/ystack/yconverge/verify"

step: verify.#Step & {
	checks: [{
		kind:        "exec"
		command:     "kubectl --context=$CONTEXT -n default get job example-replace-job"
		timeout:     "10s"
		description: "replace-mode Job exists"
	}]
}
