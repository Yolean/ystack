package gateway

import (
	"yolean.se/ystack/yconverge/converge"
	"yolean.se/ystack/k3s/10-gateway-api:gateway_api"
)

_dep_crds: gateway_api.step

step: converge.#Step & {
	checks: [
		{
			kind:        "exec"
			command:     "[ -z \"$OVERRIDE_IP\" ] || kubectl --context=$CONTEXT -n ystack annotate gateway ystack yolean.se/override-ip=$OVERRIDE_IP --overwrite"
			timeout:     "10s"
			description: "annotate gateway with override-ip (if set)"
		},
		{
			kind:        "exec"
			command:     "y-k8s-ingress-hosts --context=$CONTEXT --ensure || echo 'WARNING: /etc/hosts update failed (may need manual sudo)'"
			timeout:     "10s"
			description: "update /etc/hosts for gateway routes"
		},
		{
			kind:      "wait"
			resource:  "gateway/ystack"
			namespace: "ystack"
			for:       "condition=Programmed"
			timeout:   "60s"
		},
	]
}
