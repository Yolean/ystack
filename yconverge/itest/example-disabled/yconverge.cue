package example_disabled

import "yolean.se/ystack/yconverge/converge"

step: converge.#Step & {
	checks: [{
		kind:        "exec"
		command:     "false"
		timeout:     "5s"
		description: "should never run"
	}]
}
