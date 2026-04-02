package gateway_api

import (
	"yolean.se/ystack/cue/converge"
	"yolean.se/ystack/k3s/00-namespace-ystack:namespace_ystack"
)

_deps: namespace_ystack.step

step: converge.#Step & {
	kustomization: "k3s/10-gateway-api"
	checks: [{
		kind:     "wait"
		resource: "crd/gateways.gateway.networking.k8s.io"
		for:      "condition=Established"
		timeout:  "60s"
	}]
}
