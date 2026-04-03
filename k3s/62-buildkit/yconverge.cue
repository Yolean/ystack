package buildkit

import (
	"yolean.se/ystack/cue/converge"
	"yolean.se/ystack/k3s/60-builds-registry:builds_registry"
)

_dep_registry: builds_registry.step

step: converge.#Step & {
	checks: [{
		kind:        "exec"
		command:     "kubectl --context=$CONTEXT -n ystack get statefulset buildkitd"
		timeout:     "10s"
		description: "buildkitd statefulset exists"
	}]
}
