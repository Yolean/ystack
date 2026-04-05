package blobs

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/k3s/30-blobs-ystack:blobs_ystack"
)

_dep_ystack: blobs_ystack.step

step: verify.#Step & {
	checks: [{
		kind:      "rollout"
		resource:  "deploy/versitygw"
		namespace: "blobs"
		timeout:   "60s"
	}]
}
