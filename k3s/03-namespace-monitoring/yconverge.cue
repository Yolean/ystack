package namespace_monitoring

import "yolean.se/ystack/cue/converge"

step: converge.#Step & {
	checks: []
}
