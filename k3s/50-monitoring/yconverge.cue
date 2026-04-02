package monitoring

import (
	"yolean.se/ystack/cue/converge"
	"yolean.se/ystack/k3s/11-monitoring-operator:monitoring_operator"
)

_deps: monitoring_operator.step

step: converge.#Step & {
	kustomization: "k3s/50-monitoring"
	namespace:     "monitoring"
	checks: [{
		kind:      "rollout"
		resource:  "deploy/kube-state-metrics"
		namespace: "monitoring"
		timeout:   "60s"
	}]
}
