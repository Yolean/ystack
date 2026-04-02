package namespace_blobs

import "yolean.se/ystack/cue/converge"

step: converge.#Step & {
	kustomization: "k3s/01-namespace-blobs"
	namespace:     "blobs"
	checks: []
}
