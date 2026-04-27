package example_namespace

import "yolean.se/ystack/yconverge/verify"

step: verify.#Step & {
	checks: [{
		kind:     "wait"
		resource: "Namespace/itest"
		for:      "jsonpath={.status.phase}=Active"
		timeout:  "10s"
	}]
}
