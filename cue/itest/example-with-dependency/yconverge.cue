package example_with_dependency

import (
	"yolean.se/ystack/cue/converge"
	"yolean.se/ystack/cue/itest/example-configmap:example_configmap"
)

step: converge.#Step & {
	kustomization: "cue/itest/example-with-dependency"
	namespace:     "itest"
	prechecks:     example_configmap.step.checks
	checks: [{
		kind:        "exec"
		command:     "kubectl --context=$CONTEXT -n itest get configmap itest-dependent"
		timeout:     "10s"
		description: "dependent configmap exists"
	}]
}
