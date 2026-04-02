package y_kustomize_secrets_init

import (
	"yolean.se/ystack/cue/converge"
	"yolean.se/ystack/k3s/00-namespace-ystack:namespace_ystack"
)

_deps: namespace_ystack.step

step: converge.#Step & {
	kustomization: "k3s/09-y-kustomize-secrets-init"
	namespace:     "ystack"
	checks: []
}
