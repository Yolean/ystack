package example_configmap

import (
	"yolean.se/ystack/cue/converge"
	"yolean.se/ystack/cue/itest/example-namespace:example_namespace"
)

step: converge.#Step & {
	kustomization: "cue/itest/example-configmap"
	namespace:     "itest"
	prechecks:     example_namespace.step.checks
	checks: [{
		kind:        "exec"
		command:     "kubectl --context=$CONTEXT -n itest get configmap itest-config"
		timeout:     "10s"
		description: "configmap exists"
	}]
}
