package buckety

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/k3s/30-blobs:blobs"
	"yolean.se/ystack/k3s/40-kafka:kafka"
)

// Buckety-controller talks to both backends on first reconcile;
// staging it after the backing services come up avoids early
// connection failures and lets the controller's first status
// stamp succeed.
_dep_blobs: blobs.step
_dep_kafka: kafka.step

step: verify.#Step & {
	checks: [{
		kind:      "rollout"
		resource:  "deploy/buckety-controller"
		namespace: "buckety"
		timeout:   "120s"
	}]
}
