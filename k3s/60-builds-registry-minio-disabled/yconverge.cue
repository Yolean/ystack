package builds_registry_minio_disabled

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/k3s/15-buckety-minio-disabled:buckety_minio_disabled"
	"yolean.se/ystack/k3s/30-blobs-minio-disabled:blobs_minio_disabled"
)

_dep_buckety: buckety_minio_disabled.step
_dep_blobs:   blobs_minio_disabled.step

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
		{
			kind:        "exec"
			command:     "y-k8s-ingress-hosts --context=$CONTEXT -write"
			timeout:     "10s"
			description: "update /etc/hosts for gateway routes"
		},
	]
}
