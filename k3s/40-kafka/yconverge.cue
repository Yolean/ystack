package kafka

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/k3s/40-kafka-ystack:kafka_ystack"
)

_dep_ystack: kafka_ystack.step

step: verify.#Step & {
	checks: [
		{
			kind:      "rollout"
			resource:  "statefulset/redpanda"
			namespace: "kafka"
			timeout:   "120s"
		},
		{
			kind:        "exec"
			command:     "kubectl --context=$CONTEXT exec -n kafka redpanda-0 -c redpanda -- rpk cluster info"
			timeout:     "30s"
			description: "redpanda cluster healthy"
		},
	]
}
