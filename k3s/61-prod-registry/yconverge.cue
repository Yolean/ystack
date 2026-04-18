package prod_registry

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/k3s/00-namespace-ystack:namespace_ystack"
)

_dep_ns: namespace_ystack.step

step: verify.#Step & {
	checks: []
}
