package kafka_ystack

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/k3s/02-namespace-kafka:namespace_kafka"
	"yolean.se/ystack/k3s/29-y-kustomize:y_kustomize"
)

_dep_ns:        namespace_kafka.step
_dep_kustomize: y_kustomize.step

step: verify.#Step & {
	// y-kustomize watches secrets via API — no restart needed.
	checks: [
		{
			kind:        "exec"
			command:     "curl -sSf --connect-timeout 2 --max-time 5 http://y-kustomize.ystack.svc.cluster.local/v1/kafka/setup-topic-job/base-for-annotations.yaml >/dev/null"
			timeout:     "30s"
			description: "y-kustomize serving kafka bases"
		},
		{
			kind:        "exec"
			command:     "curl -sSf --connect-timeout 2 --max-time 5 http://y-kustomize.ystack.svc.cluster.local/v1/blobs/setup-bucket-job/base-for-annotations.yaml >/dev/null"
			timeout:     "30s"
			description: "y-kustomize serving blobs bases"
		},
	]
}
