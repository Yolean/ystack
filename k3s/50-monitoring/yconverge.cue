package monitoring

import (
	"yolean.se/ystack/cue/converge"
	"yolean.se/ystack/k3s/11-monitoring-operator:monitoring_operator"
)

_dep_operator: monitoring_operator.step

step: converge.#Step & {
	checks: [{
		kind:      "rollout"
		resource:  "deploy/kube-state-metrics"
		namespace: "monitoring"
		timeout:   "60s"
	}]
}
