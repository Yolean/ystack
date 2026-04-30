package example_db_single

import "yolean.se/ystack/yconverge/verify"

step: verify.#Step & {
	checks: [
		{
			kind:     "wait"
			resource: "statefulset/database"
			for:      "jsonpath={.status.currentReplicas}=1"
			timeout:  "30s"
		},
		{
			kind:        "exec"
			command:     #"kubectl --context=$CONTEXT -n $NS_GUESS get pdb -o jsonpath='{.items[*].spec.minAvailable}' | tr ' ' '\n' | awk '$1 > 1 { exit 1 }'"#
			description: "no PDB requires more than 1 replica (single-replica safety)"
			timeout:     "5s"
		},
	]
}
