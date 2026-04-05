package namespace_monitoring

import "yolean.se/ystack/yconverge/converge"

step: converge.#Step & {
	checks: []
}
