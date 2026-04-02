package kafka_ystack

import (
	"yolean.se/ystack/cue/converge"
	"yolean.se/ystack/k3s/02-namespace-kafka:namespace_kafka"
	"yolean.se/ystack/k3s/29-y-kustomize:y_kustomize"
)

_dep_ns:        namespace_kafka.step
_dep_kustomize: y_kustomize.step

step: converge.#Step & {
	kustomization: "k3s/40-kafka-ystack"
	namespace:     "kafka"
	actions: [{
		kind:        "action"
		command:     "kubectl --context=$CONTEXT -n ystack rollout restart deploy/y-kustomize && kubectl --context=$CONTEXT -n ystack rollout status deploy/y-kustomize --timeout=60s"
		description: "restart y-kustomize to pick up kafka secrets"
	}]
	checks: [
		{
			kind:        "exec"
			command:     "kubectl --context=$CONTEXT get --raw /api/v1/namespaces/ystack/services/y-kustomize:80/proxy/v1/blobs/setup-bucket-job/base-for-annotations.yaml"
			timeout:     "60s"
			description: "y-kustomize serving blobs bases"
		},
		{
			kind:        "exec"
			command:     "kubectl --context=$CONTEXT get --raw /api/v1/namespaces/ystack/services/y-kustomize:80/proxy/v1/kafka/setup-topic-job/base-for-annotations.yaml"
			timeout:     "60s"
			description: "y-kustomize serving kafka bases"
		},
	]
}
