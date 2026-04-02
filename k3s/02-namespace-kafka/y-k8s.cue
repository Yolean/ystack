package namespace_kafka

import "yolean.se/ystack/cue/converge"

step: converge.#Step & {
	kustomization: "k3s/02-namespace-kafka"
	namespace:     "kafka"
	checks: []
}
