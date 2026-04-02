package blobs_ystack

import (
	"yolean.se/ystack/cue/converge"
	"yolean.se/ystack/k3s/01-namespace-blobs:namespace_blobs"
	"yolean.se/ystack/k3s/29-y-kustomize:y_kustomize"
)

_dep_ns:        namespace_blobs.step
_dep_kustomize: y_kustomize.step

step: converge.#Step & {
	kustomization: "k3s/30-blobs-ystack"
	namespace:     "blobs"
	checks: []
}
