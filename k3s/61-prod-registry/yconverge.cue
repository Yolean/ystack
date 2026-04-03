package prod_registry

import (
	"yolean.se/ystack/cue/converge"
	"yolean.se/ystack/k3s/00-namespace-ystack:namespace_ystack"
)

_dep_ns: namespace_ystack.step

step: converge.#Step & {
	checks: []
}
