package example_db_single

import "yolean.se/ystack/yconverge/verify"

step: verify.#Step & {
	checks: [{
		kind:     "wait"
		resource: "statefulset/database"
		for:      "jsonpath={.status.currentReplicas}=1"
		timeout:  "30s"
	}]
}
