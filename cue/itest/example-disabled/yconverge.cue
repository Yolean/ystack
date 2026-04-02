package example_disabled

import "yolean.se/ystack/cue/converge"

step: converge.#Step & {
	kustomization: "cue/itest/example-disabled"
	namespace:     "itest"
	enabled:       false
	checks: [{
		kind:        "exec"
		command:     "false"
		timeout:     "5s"
		description: "should never run"
	}]
}
