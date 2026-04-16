package kafka_ystack

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/k3s/02-namespace-kafka:namespace_kafka"
	"yolean.se/ystack/k3s/29-y-kustomize:y_kustomize"
)

_dep_ns:        namespace_kafka.step
_dep_kustomize: y_kustomize.step

step: verify.#Step & {
	checks: [
		{
			kind:        "exec"
			command:     "kubectl --context=$CONTEXT -n ystack rollout restart deploy/y-kustomize && kubectl --context=$CONTEXT -n ystack rollout status deploy/y-kustomize --timeout=60s"
			timeout:     "90s"
			description: "restart y-kustomize to pick up kafka secrets"
		},
		{
			// After restart, wait for y-kustomize to serve kafka content via Traefik.
			// This is the path kustomize uses — if this works, builds will resolve.
			// Traefik checks first because they're the real consumer requirement.
			kind:        "exec"
			command:     "curl -sSf --connect-timeout 2 --max-time 5 http://y-kustomize.ystack.svc.cluster.local/v1/kafka/setup-topic-job/base-for-annotations.yaml >/dev/null"
			timeout:     "30s"
			description: "y-kustomize serving kafka bases (Traefik)"
		},
		{
			// After the second restart (kafka), the blobs secret may take up to
			// 60-90s to propagate via kubelet volume sync. This is a known
			// Kubernetes limitation (syncInterval + cache TTL).
			kind:        "exec"
			command:     "curl -sSf --connect-timeout 2 --max-time 5 http://y-kustomize.ystack.svc.cluster.local/v1/blobs/setup-bucket-job/base-for-annotations.yaml >/dev/null"
			timeout:     "90s"
			description: "y-kustomize serving blobs bases (Traefik)"
		},
	]
}
