package checks

// Parameterized check set for the database statefulset.
// Variants (single, distributed) import and unify with their own replica count.
#DbChecks: {
	replicas: int
	list: [{
		kind:     "wait"
		resource: "statefulset/database"
		for:      "jsonpath={.status.currentReplicas}=\(replicas)"
		timeout:  "30s"
	}]
}
