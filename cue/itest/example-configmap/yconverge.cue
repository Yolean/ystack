package example_configmap

import (
	"yolean.se/ystack/cue/converge"
	"yolean.se/ystack/cue/itest/example-namespace:example_namespace"
)

_dep_ns: example_namespace.step

step: converge.#Step & {
	checks: [{
		kind:        "exec"
		command:     "kubectl --context=$CONTEXT -n itest get configmap itest-config"
		timeout:     "10s"
		description: "configmap exists"
	}]
}
