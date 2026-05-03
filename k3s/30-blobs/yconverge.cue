package blobs

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/k3s/01-namespace-blobs:namespace_blobs"
)

_dep_ns: namespace_blobs.step

step: verify.#Step & {
	checks: [{
		kind:      "rollout"
		resource:  "deploy/versitygw"
		namespace: "blobs"
		timeout:   "60s"
	}]
}
