package gateway

import (
	"yolean.se/ystack/cue/converge"
	"yolean.se/ystack/k3s/10-gateway-api:gateway_api"
)

_deps: gateway_api.step

step: converge.#Step & {
	kustomization: "k3s/20-gateway"
	namespace:     "ystack"
	actions: [{
		kind:        "action"
		command:     "y-k8s-ingress-hosts --context=$CONTEXT --ensure"
		description: "update /etc/hosts for gateway routes"
	}]
	checks: [{
		kind:      "wait"
		resource:  "gateway/ystack"
		namespace: "ystack"
		for:       "condition=Programmed"
		timeout:   "60s"
	}]
}
