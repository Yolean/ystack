package example_db_single

import (
	"list"
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/yconverge/itest/example-db/checks"
)

_shared: checks.#DbChecks & {replicas: 1}

step: verify.#Step & {
	checks: list.Concat([_shared.list, [{
		kind:        "exec"
		command:     #"kubectl --context=$CONTEXT -n $NS_GUESS get pdb -o jsonpath='{.items[*].spec.minAvailable}' | tr ' ' '\n' | awk '$1 > 1 { exit 1 }'"#
		description: "no PDB requires more than 1 replica (single-replica safety)"
		timeout:     "5s"
	}]])
}
