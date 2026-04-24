package blobs_ystack

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/k3s/01-namespace-blobs:namespace_blobs"
	"yolean.se/ystack/k3s/29-y-kustomize:y_kustomize"
)

_dep_ns:        namespace_blobs.step
_dep_kustomize: y_kustomize.step

step: verify.#Step & {
	// y-kustomize watches secrets via API — no restart needed.
	checks: [{
		kind:        "exec"
		command:     "curl -sSf --connect-timeout 2 --max-time 5 http://y-kustomize:8944/v1/blobs/setup-bucket-job/base-for-annotations.yaml >/dev/null"
		timeout:     "30s"
		description: "y-kustomize serving blobs bases"
	}]
}
