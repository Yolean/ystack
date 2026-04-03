package namespace_ystack

import "yolean.se/ystack/cue/converge"

step: converge.#Step & {
	checks: []
}
