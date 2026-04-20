package y_kustomize

import "yolean.se/ystack/yconverge/verify"

// No dependencies — y-kustomize watches secrets via API, doesn't
// need them pre-created. Gateway API is assumed by provisioner.

step: verify.#Step & {
	checks: [
		{
			kind:      "rollout"
			resource:  "deploy/y-kustomize"
			namespace: "ystack"
			timeout:   "120s"
		},
		{
			kind:        "exec"
			command:     "y-k8s-ingress-hosts --context=$CONTEXT -write || echo 'WARNING: /etc/hosts update failed (may need manual sudo)'"
			timeout:     "10s"
			description: "update /etc/hosts for y-kustomize HTTPRoute"
		},
	]
}
