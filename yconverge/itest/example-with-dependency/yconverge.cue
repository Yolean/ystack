package example_with_dependency

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/yconverge/itest/example-configmap:example_configmap"
)

_dep_config: example_configmap.step

step: verify.#Step & {
	checks: [{
		kind:        "exec"
		command:     "kubectl --context=$CONTEXT -n itest get configmap itest-dependent"
		timeout:     "10s"
		description: "dependent configmap exists"
	}]
}
