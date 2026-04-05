package monitoring_operator

import (
	"yolean.se/ystack/yconverge/converge"
	"yolean.se/ystack/k3s/03-namespace-monitoring:namespace_monitoring"
)

_dep_ns: namespace_monitoring.step

step: converge.#Step & {
	checks: [{
		kind:      "rollout"
		resource:  "deploy/prometheus-operator"
		namespace: "default"
		timeout:   "120s"
	}]
}
