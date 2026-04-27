package y_kustomize

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/k3s/20-gateway:gateway"
)

// HTTPRoute attaches to the ystack Gateway, so the Gateway must be
// Programmed before /health can succeed. y-kustomize itself watches
// secrets via API and doesn't need them pre-created.

_dep_gateway: gateway.step

step: verify.#Step & {
	checks: [
		// /etc/hosts must be updated before the /health probe -- the probe
		// resolves "y-kustomize" via the file we just wrote.
		{
			kind:        "exec"
			command:     "y-k8s-ingress-hosts --context=$CONTEXT -write || echo 'WARNING: /etc/hosts update failed (may need manual sudo)'"
			timeout:     "10s"
			description: "update /etc/hosts for y-kustomize HTTPRoute"
		},
		// /health goes through the canonical Gateway:80 -> HTTPRoute -> Service:8944
		// path. y-cluster's qemu provisioner forwards host:80 to guest:80; the
		// EG-managed LoadBalancer Service on port 80 backs the Gateway listener.
		{
			kind:        "exec"
			command:     "for i in $(seq 1 30); do curl -sSf --max-time 2 http://y-kustomize/health >/dev/null && break; sleep 2; done && curl -sSf --max-time 5 http://y-kustomize/health >/dev/null"
			timeout:     "60s"
			description: "y-kustomize /health responds via Gateway"
		},
	]
}
