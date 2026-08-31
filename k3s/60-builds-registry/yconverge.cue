package builds_registry

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/k3s/15-buckety:buckety"
	"yolean.se/ystack/k3s/30-blobs:blobs"
)

// buckety provisions both of the registry's backing resources: the
// kafka topic and the s3 bucket. blobs is a separate dep because the
// s3 driver needs versitygw's endpoint reachable to create the
// bucket, so the Deployment and Service must be up first.
_dep_buckety: buckety.step
_dep_blobs:   blobs.step

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
