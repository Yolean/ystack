package builds_registry

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/k3s/31-blobs-y-kustomize:blobs_y_kustomize"
	"yolean.se/ystack/k3s/41-kafka-y-kustomize:kafka_y_kustomize"
	"yolean.se/ystack/k3s/29-y-kustomize:y_kustomize"
)

_dep_blobs:     blobs_y_kustomize.step
_dep_kafka:     kafka_y_kustomize.step
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
