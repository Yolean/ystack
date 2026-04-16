package example_db_distributed

import (
	"yolean.se/ystack/yconverge/verify"
	"yolean.se/ystack/yconverge/itest/example-db/checks"
)

_shared: checks.#DbChecks & {replicas: 3}

step: verify.#Step & {
	checks: _shared.list
}
