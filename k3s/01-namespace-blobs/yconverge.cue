package namespace_blobs

import "yolean.se/ystack/cue/converge"

step: converge.#Step & {
	checks: []
}
