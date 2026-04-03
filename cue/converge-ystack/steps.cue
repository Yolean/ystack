package converge_ystack

import (
	"yolean.se/ystack/k3s/00-namespace-ystack:namespace_ystack"
	"yolean.se/ystack/k3s/01-namespace-blobs:namespace_blobs"
	"yolean.se/ystack/k3s/02-namespace-kafka:namespace_kafka"
	"yolean.se/ystack/k3s/03-namespace-monitoring:namespace_monitoring"
	"yolean.se/ystack/k3s/09-y-kustomize-secrets-init:y_kustomize_secrets_init"
	"yolean.se/ystack/k3s/10-gateway-api:gateway_api"
	"yolean.se/ystack/k3s/11-monitoring-operator:monitoring_operator"
	"yolean.se/ystack/k3s/20-gateway:gateway"
	"yolean.se/ystack/k3s/29-y-kustomize:y_kustomize"
	"yolean.se/ystack/k3s/30-blobs-ystack:blobs_ystack"
	"yolean.se/ystack/k3s/30-blobs:blobs"
	"yolean.se/ystack/k3s/30-blobs-minio-disabled:blobs_minio_disabled"
	"yolean.se/ystack/k3s/40-kafka-ystack:kafka_ystack"
	"yolean.se/ystack/k3s/40-kafka:kafka"
	"yolean.se/ystack/k3s/50-monitoring:monitoring"
	"yolean.se/ystack/k3s/60-builds-registry:builds_registry"
	"yolean.se/ystack/k3s/61-prod-registry:prod_registry"
	"yolean.se/ystack/k3s/62-buildkit:buildkit"
)

import "yolean.se/ystack/cue/converge"

_entry: {
	path:  string
	step:  converge.#Step
}

// All steps in dependency order.
steps: [..._entry] & [
	{path: "k3s/00-namespace-ystack", step: namespace_ystack.step},
	{path: "k3s/01-namespace-blobs", step: namespace_blobs.step},
	{path: "k3s/02-namespace-kafka", step: namespace_kafka.step},
	{path: "k3s/03-namespace-monitoring", step: namespace_monitoring.step},
	{path: "k3s/09-y-kustomize-secrets-init", step: y_kustomize_secrets_init.step},
	{path: "k3s/10-gateway-api", step: gateway_api.step},
	{path: "k3s/11-monitoring-operator", step: monitoring_operator.step},
	{path: "k3s/20-gateway", step: gateway.step},
	{path: "k3s/29-y-kustomize", step: y_kustomize.step},
	{path: "k3s/30-blobs-ystack", step: blobs_ystack.step},
	{path: "k3s/30-blobs", step: blobs.step},
	{path: "k3s/30-blobs-minio-disabled", step: blobs_minio_disabled.step},
	{path: "k3s/40-kafka-ystack", step: kafka_ystack.step},
	{path: "k3s/40-kafka", step: kafka.step},
	{path: "k3s/50-monitoring", step: monitoring.step},
	{path: "k3s/60-builds-registry", step: builds_registry.step},
	{path: "k3s/61-prod-registry", step: prod_registry.step},
	{path: "k3s/62-buildkit", step: buildkit.step},
]
