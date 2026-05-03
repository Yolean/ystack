package example_configmap

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/yconverge/itest/example-namespace:example_namespace"
)

_dep_ns: example_namespace.step

step: verify.#Step & {
	checks: [{
		kind:        "exec"
		command:     "kubectl --context=$CONTEXT -n itest get configmap itest-config"
		timeout:     "10s"
		description: "configmap exists"
	}]
}
