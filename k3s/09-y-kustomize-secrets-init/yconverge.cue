package y_kustomize_secrets_init

import (
	"yolean.se/ystack/yconverge/converge"
	"yolean.se/ystack/k3s/00-namespace-ystack:namespace_ystack"
)

_dep_ns: namespace_ystack.step

step: converge.#Step & {
	checks: []
}
