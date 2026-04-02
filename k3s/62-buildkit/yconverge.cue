package buildkit

import (
	"yolean.se/ystack/cue/converge"
	"yolean.se/ystack/k3s/60-builds-registry:builds_registry"
)

_deps: builds_registry.step

step: converge.#Step & {
	kustomization: "k3s/62-buildkit"
	namespace:     "ystack"
	checks: [{
		kind:        "exec"
		command:     "kubectl --context=$CONTEXT -n ystack get statefulset buildkitd"
		timeout:     "10s"
		description: "buildkitd statefulset exists"
	}]
}
