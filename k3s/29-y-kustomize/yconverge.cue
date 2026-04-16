package y_kustomize

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/k3s/09-y-kustomize-secrets-init:y_kustomize_secrets_init"
	"yolean.se/ystack/k3s/20-gateway:gateway"
)

_dep_secrets: y_kustomize_secrets_init.step
_dep_gateway: gateway.step

step: verify.#Step & {
	checks: [{
		kind:      "rollout"
		resource:  "deploy/y-kustomize"
		namespace: "ystack"
		timeout:   "120s"
	}]
}
