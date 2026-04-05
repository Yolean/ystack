package blobs

import (
	"yolean.se/ystack/yconverge/converge"
	"yolean.se/ystack/k3s/30-blobs-ystack:blobs_ystack"
)

_dep_ystack: blobs_ystack.step

step: converge.#Step & {
	checks: [{
		kind:      "rollout"
		resource:  "deploy/versitygw"
		namespace: "blobs"
		timeout:   "60s"
	}]
}
