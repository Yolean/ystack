package y_kustomize

import "yolean.se/ystack/yconverge/verify"

// No dependencies — y-kustomize watches secrets via API, doesn't
// need them pre-created. Gateway API is assumed by provisioner.

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
		// /health is reachable whether the in-cluster Deployment is running
		// OR `y-cluster serve` runs on the host bound to 127.0.0.1:8944.
		// When the y-cluster v0.3.0 image ships and the in-cluster Deployment
		// rolls out, this probe still passes with no test changes.
		{
			kind:        "exec"
			command:     "for i in $(seq 1 30); do curl -sSf --max-time 2 http://y-kustomize:8944/health >/dev/null && break; sleep 2; done && curl -sSf --max-time 5 http://y-kustomize:8944/health >/dev/null"
			timeout:     "60s"
			description: "y-kustomize /health responds (in-cluster Deployment or host-local y-cluster serve)"
		},
	]
}
