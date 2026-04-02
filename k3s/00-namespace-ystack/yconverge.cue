package namespace_ystack

import "yolean.se/ystack/cue/converge"

step: converge.#Step & {
	kustomization: "k3s/00-namespace-ystack"
	namespace:     "ystack"
	checks: []
}
