package namespace_monitoring

import "yolean.se/ystack/cue/converge"

step: converge.#Step & {
	kustomization: "k3s/03-namespace-monitoring"
	namespace:     "monitoring"
	checks: []
}
