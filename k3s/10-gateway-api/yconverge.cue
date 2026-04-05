package gateway_api

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/k3s/00-namespace-ystack:namespace_ystack"
)

_dep_ns: namespace_ystack.step

step: verify.#Step & {
	checks: [{
		kind:        "exec"
		command:     "for i in $(seq 1 30); do kubectl --context=$CONTEXT wait --for=condition=Established --timeout=2s crd/gateways.gateway.networking.k8s.io 2>/dev/null && break; sleep 2; done && kubectl --context=$CONTEXT wait --for=condition=Established --timeout=5s crd/gateways.gateway.networking.k8s.io"
		timeout:     "120s"
		description: "gateway API CRDs established"
	}]
}
