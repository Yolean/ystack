package blobs_minio_disabled

import "yolean.se/ystack/cue/converge"

step: converge.#Step & {
	kustomization: "k3s/30-blobs-minio-disabled"
	namespace:     "blobs"
	enabled:       false
	checks: []
}
