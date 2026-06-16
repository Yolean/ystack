package buckety

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/k3s/40-kafka:kafka"
)

// Buckety-controller talks to the kafka cluster on first reconcile;
// staging it after 40-kafka avoids early-reconcile noise.
_dep_kafka: kafka.step

step: verify.#Step & {
	checks: [{
		kind:      "rollout"
		resource:  "deploy/buckety-controller"
		namespace: "buckety"
		timeout:   "120s"
	}]
}
