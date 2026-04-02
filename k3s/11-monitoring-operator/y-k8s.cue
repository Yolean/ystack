package monitoring_operator

import (
	"yolean.se/ystack/cue/converge"
	"yolean.se/ystack/k3s/03-namespace-monitoring:namespace_monitoring"
)

_deps: namespace_monitoring.step

step: converge.#Step & {
	kustomization: "k3s/11-monitoring-operator"
	namespace:     "monitoring"
	checks: [{
		kind:      "rollout"
		resource:  "deploy/prometheus-operator"
		namespace: "default"
		timeout:   "120s"
	}]
}
