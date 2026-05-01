package blobs_y_kustomize

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/k3s/30-blobs:blobs"
	"yolean.se/ystack/k3s/29-y-kustomize:y_kustomize"
)

_dep_blobs:     blobs.step
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
