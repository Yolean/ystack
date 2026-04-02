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

// All steps in dependency order. The order here matches the DAG
// but CUE imports enforce the actual dependency constraints.
steps: [
	namespace_ystack.step,
	namespace_blobs.step,
	namespace_kafka.step,
	namespace_monitoring.step,
	y_kustomize_secrets_init.step,
	gateway_api.step,
	monitoring_operator.step,
	gateway.step,
	y_kustomize.step,
	blobs_ystack.step,
	blobs.step,
	blobs_minio_disabled.step,
	kafka_ystack.step,
	kafka.step,
	monitoring.step,
	builds_registry.step,
	prod_registry.step,
	buildkit.step,
]
