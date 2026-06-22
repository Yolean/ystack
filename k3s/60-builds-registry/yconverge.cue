package builds_registry

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/k3s/15-buckety:buckety"
	"yolean.se/ystack/k3s/30-blobs:blobs"
)

// y-kustomize is retired from this dep chain: kafka topic and
// blobs bucket are both provisioned via Buckety. blobs (the
// versitygw Deployment + Service) is still needed because the
// s3 buckety driver talks to its admin/data endpoint.
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
