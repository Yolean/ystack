package kafka

import (
	"yolean.se/ystack/cue/converge"
	"yolean.se/ystack/k3s/40-kafka-ystack:kafka_ystack"
)

_deps: kafka_ystack.step

step: converge.#Step & {
	kustomization: "k3s/40-kafka"
	namespace:     "kafka"
	checks: [{
		kind:        "exec"
		command:     "kubectl --context=$CONTEXT exec -n kafka redpanda-0 -c redpanda -- rpk cluster info"
		timeout:     "120s"
		description: "redpanda cluster healthy"
	}]
}
