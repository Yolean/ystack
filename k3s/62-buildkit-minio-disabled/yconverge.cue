package buildkit_minio_disabled

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/k3s/60-builds-registry-minio-disabled:builds_registry_minio_disabled"
)

_dep_registry: builds_registry_minio_disabled.step

step: verify.#Step & {
	checks: [
		{
			kind:        "exec"
			command:     "kubectl --context=$CONTEXT -n ystack get statefulset buildkitd"
			timeout:     "10s"
			description: "buildkitd statefulset exists"
		},
		{
			kind:        "exec"
			command:     "y-k8s-ingress-hosts --context=$CONTEXT -write"
			timeout:     "10s"
			description: "update /etc/hosts for gateway routes"
		},
	]
}
