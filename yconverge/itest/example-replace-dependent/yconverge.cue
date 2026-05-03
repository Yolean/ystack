package example_replace_dependent

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/yconverge/itest/example-replace:example_replace"
)

_dep_replace: example_replace.step

step: verify.#Step & {
	checks: [{
		kind:        "exec"
		command:     "kubectl --context=$CONTEXT -n default get configmap example-replace-dependent"
		timeout:     "10s"
		description: "dependent configmap exists after replace step"
	}]
}
