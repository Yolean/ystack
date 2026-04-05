package blobs_minio_disabled

import "yolean.se/ystack/yconverge/converge"

step: converge.#Step & {
	checks: []
}
