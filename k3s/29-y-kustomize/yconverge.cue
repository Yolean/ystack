package y_kustomize

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/k3s/09-y-kustomize-secrets-init:y_kustomize_secrets_init"
)

// Gateway API is assumed configured by the provisioner.
_dep_secrets: y_kustomize_secrets_init.step

step: verify.#Step & {
	checks: [{
		kind:      "rollout"
		resource:  "deploy/y-kustomize"
		namespace: "ystack"
		timeout:   "120s"
	}]
}
