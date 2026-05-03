package example_db_distributed

import "yolean.se/ystack/yconverge/verify"

step: verify.#Step & {
	checks: [{
		kind:     "wait"
		resource: "statefulset/database"
		for:      "jsonpath={.status.currentReplicas}=3"
		timeout:  "30s"
	}]
}
