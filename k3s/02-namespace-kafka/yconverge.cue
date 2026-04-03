package namespace_kafka

import "yolean.se/ystack/cue/converge"

step: converge.#Step & {
	checks: []
}
