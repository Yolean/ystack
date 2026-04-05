package monitoring

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/k3s/11-monitoring-operator:monitoring_operator"
)

_dep_operator: monitoring_operator.step

step: verify.#Step & {
	checks: [{
		kind:      "rollout"
		resource:  "deploy/kube-state-metrics"
		namespace: "monitoring"
		timeout:   "60s"
	}]
}
