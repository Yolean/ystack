package example_namespace

import "yolean.se/ystack/cue/converge"

step: converge.#Step & {
	kustomization: "cue/itest/example-namespace"
	namespace:     "itest"
	checks: [{
		kind:     "wait"
		resource: "ns/itest"
		for:      "jsonpath={.status.phase}=Active"
		timeout:  "10s"
	}]
}
