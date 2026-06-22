package buckety_minio_disabled

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/k3s/30-blobs-minio-disabled:blobs_minio_disabled"
	"yolean.se/ystack/k3s/40-kafka:kafka"
)

_dep_blobs: blobs_minio_disabled.step
_dep_kafka: kafka.step

step: verify.#Step & {
	checks: [{
		kind:      "rollout"
		resource:  "deploy/buckety-controller"
		namespace: "buckety"
		timeout:   "120s"
	}]
}
