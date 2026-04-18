package example_disabled

import "yolean.se/ystack/yconverge/verify"

step: verify.#Step & {
	checks: [{
		kind:        "exec"
		command:     "false"
		timeout:     "5s"
		description: "should never run"
	}]
}
