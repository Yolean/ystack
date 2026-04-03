package blobs_minio_disabled

import "yolean.se/ystack/cue/converge"

step: converge.#Step & {
	checks: []
}
