# ystack metrics-v2 experiment

Test vanilla Prometheus with Thanos and GreptimeDB on a local single-node ystack cluster.

Starting point: branch `local-cluster-provision-alignment`.

## Prerequisites

- [ ] Merge or rebase onto `local-cluster-provision-alignment`
- [ ] Verify `y-cluster-provision-k3d` works: `KUBECONFIG=~/.kube/ystack-experiment y-cluster-provision-k3d`
- [ ] Confirm monitoring stack is running: `y-cluster-validate-ystack --context=local`

## 1. Remove prometheus-operator

Apply [Steps 1-6 from the vanilla prometheus plan](ystack-vanilla-prometheus.md#step-1-create-prometheus-config-files)
to replace all CRDs with plain Kubernetes resources.

- [ ] Create Prometheus config and rules files ([Step 1](ystack-vanilla-prometheus.md#step-1-create-prometheus-config-files))
- [ ] Replace Prometheus CRD with Deployment ([Step 2](ystack-vanilla-prometheus.md#step-2-replace-prometheus-crd-with-deployment))
- [ ] Replace Alertmanager CRD with Deployment ([Step 3](ystack-vanilla-prometheus.md#step-3-replace-alertmanager-crd-with-deployment))
- [ ] Remove PodMonitor and ServiceMonitor CRDs ([Step 4](ystack-vanilla-prometheus.md#step-4-remove-crd-resources-from-node-exporter-and-kube-state-metrics))
- [ ] Simplify -now overlay kustomizations ([Step 5](ystack-vanilla-prometheus.md#step-5-simplify--now-overlay-kustomizations))
- [ ] Delete prometheus-operator and update `k3s/30-monitoring` ([Step 6](ystack-vanilla-prometheus.md#step-6-delete-prometheus-operator-and-update-references))
- [ ] Update converge and validate scripts ([Step 7](ystack-vanilla-prometheus.md#step-7-update-validation))
- [ ] Run the [verification checklist](ystack-vanilla-prometheus.md#verification-checklist)

## 2. Validate vanilla Prometheus

- [ ] `kustomize build k3s/30-monitoring` succeeds with no `monitoring.coreos.com` references
- [ ] Re-provision: `y-cluster-provision-k3d --teardown && y-cluster-provision-k3d`
- [ ] Prometheus UI accessible via HTTPRoute at `http://prometheus-now.monitoring.svc.cluster.local`
- [ ] Prometheus reports `reloadConfigSuccess: true` at `/api/v1/status/runtimeinfo`
- [ ] Targets page shows node-exporter and kube-state-metrics as UP
- [ ] Recording rules from `rules/node-exporter.yml` visible at `/rules`
- [ ] Alertmanager accessible at `alertmanager-main.monitoring:9093/api/v2/status`

## 3. Deploy Thanos Receive

Deploy a minimal Thanos stack to accept `remote_write` and provide a query UI.
On a single-node local cluster, zone-awareness is not testable but the component
topology matches what production will use (see
[zone-aware write patterns](checkit-monitoring-migration-mapping.md#zone-aware-write-patterns-in-detail)).

- [ ] Create `monitoring/thanos/` kustomize base with:
  - Thanos Receive StatefulSet (1 replica, emptyDir storage)
  - Thanos Query Deployment (1 replica, `--store` pointing to Receive gRPC)
  - Services for Receive remote-write (port 19291) and Query UI (port 9090)
- [ ] Apply: `kubectl --context=local apply -k monitoring/thanos/`
- [ ] Verify Receive is ready: `kubectl -n monitoring rollout status sts/thanos-receive`
- [ ] Verify Query UI loads at Thanos Query service port

## 4. Deploy GreptimeDB standalone

Deploy a single GreptimeDB instance as an alternative remote_write target.

- [ ] Create `monitoring/greptimedb/` kustomize base with:
  - GreptimeDB Deployment (standalone mode, 1 replica, emptyDir storage)
  - Service exposing remote-write (port 4000) and dashboard UI (port 4000)
- [ ] Apply: `kubectl --context=local apply -k monitoring/greptimedb/`
- [ ] Verify pod is ready: `kubectl -n monitoring rollout status deploy/greptimedb`
- [ ] Verify dashboard UI loads at `:4000/dashboard/`

## 5. Configure remote_write to both backends

Add dual remote_write to the Prometheus config so both receive the same metrics.

- [ ] Add to `monitoring/prometheus-now/prometheus.yml`:
  ```yaml
  remote_write:
    - url: http://thanos-receive.monitoring:19291/api/v1/receive
    - url: http://greptimedb.monitoring:4000/v1/prometheus/write
  ```
- [ ] Re-apply monitoring: `kubectl --context=local apply -k k3s/30-monitoring`
- [ ] Wait ~2 minutes for scrape data to propagate

## 6. Compare query results

Run the same queries against all three endpoints and compare.
Prometheus is the source of truth.

- [ ] Port-forward all three UIs:
  ```
  kubectl -n monitoring port-forward svc/prometheus-now 9090 &
  kubectl -n monitoring port-forward svc/thanos-query 9091:9090 &
  kubectl -n monitoring port-forward svc/greptimedb 4000 &
  ```
- [ ] Compare instant query: `up` (should return same target count on all three)
- [ ] Compare range query: `rate(node_cpu_seconds_total{mode="idle"}[5m])` over last 15m
- [ ] Compare recording rule result: `instance:node_cpus:count` (Thanos only, unless GreptimeDB is given rules)
- [ ] Test a [checkit-style alert expression](checkit-monitoring-migration-mapping.md#prometheusrule-crds)
  from the custom rules, e.g. `kube_pod_status_phase{phase="Pending"} > 0`
- [ ] Note any PromQL incompatibilities in GreptimeDB

## 7. Measure resource usage

- [ ] Record pod resource consumption for each backend:
  ```
  kubectl -n monitoring top pod -l app=thanos-receive
  kubectl -n monitoring top pod -l app=thanos-query
  kubectl -n monitoring top pod -l app=greptimedb
  ```
- [ ] Compare total CPU and memory: Thanos (Receive + Query) vs GreptimeDB (standalone)

## 8. Evaluate and document results

Score each backend using the [criteria from the Mimir replacement research](metrics-v2-mimir-replacement-research.md#decision-criteria-weighted).

- [ ] Query correctness (20%): did all PromQL queries return identical results?
- [ ] Operational complexity (40%): pod count, ease of setup, failure modes
- [ ] Resource usage (15%): CPU + memory footprint
- [ ] Maturity (10%): any bugs or rough edges encountered?
- [ ] Storage cost projection (15%): extrapolate from local emptyDir usage

## 9. Clean up

- [ ] Remove the losing candidate's kustomize base
- [ ] Remove the dual remote_write, keep only the winner
- [ ] Update `k3s/30-monitoring` to include the winning backend
- [ ] Re-run validate: `y-cluster-validate-ystack --context=local`
- [ ] Optionally tear down: `y-cluster-provision-k3d --teardown`
