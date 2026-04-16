# Monitoring infrastructure setup TODO

Tracks remaining work to fully converge the monitoring stack on vanilla Prometheus v3.
Ref: PR #67 review comments.

## Converge prerequisite for e2e

The `httproute prometheus-now` validation check requires the full converge sequence.
Run `y-cluster-converge-ystack --context=local` (or the relevant context) to apply all
steps including `09-prometheus-httproute`. The validate script only asserts state — it
does not create resources.

## Remaining tasks

- [ ] Drop `monitoring/prometheus-operator/` once all clusters run vanilla Prometheus
- [ ] Drop `monitoring/kube-state-metrics/` (operator CRD variant) in favor of `kube-state-metrics-now/`
- [ ] Drop `monitoring/node-exporter/node-exporter-podmonitor.yaml` — the PodMonitor CRD
      is only used by the operator; vanilla Prometheus discovers via the `metrics` port convention
- [ ] Update `k3s/30-monitoring-operator/` — either remove or gate behind a feature flag
- [ ] Migrate `monitoring/grafana/grafana-service.yaml` annotations (`prometheus.io/scrape`)
      to also expose a port named `metrics` for consistency with the pod SD convention
- [ ] Fix `k3s/09-prometheus-httproute/kustomization.yaml` — uses deprecated `bases:` key,
      should be `resources:`
- [ ] Add persistent volume for Prometheus data (currently `emptyDir {}`)
- [ ] Wire up Alertmanager to the converge and validate scripts
