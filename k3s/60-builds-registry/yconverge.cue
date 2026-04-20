package builds_registry

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/k3s/30-blobs:blobs"
	"yolean.se/ystack/k3s/40-kafka-ystack:kafka_ystack"
	"yolean.se/ystack/k3s/29-y-kustomize:y_kustomize"
)

_dep_blobs:     blobs.step
_dep_kafka:     kafka_ystack.step
_dep_kustomize: y_kustomize.step

step: verify.#Step & {
	checks: [
		{
			kind:      "rollout"
			resource:  "deploy/registry"
			namespace: "ystack"
			timeout:   "60s"
		},
		{
			kind:        "exec"
			command:     "kubectl --context=$CONTEXT get --raw /api/v1/namespaces/ystack/services/builds-registry:80/proxy/v2/_catalog"
			timeout:     "30s"
			description: "registry v2 API responds"
		},
	]
}
