# checkit monitoring: migration mapping to vanilla Prometheus

## Context

checkit is the downstream production consumer of ystack's monitoring stack.
It has extensive prometheus-operator CRD usage that must be mapped to the
vanilla Prometheus approach described in `ystack-vanilla-prometheus.md`.

This document inventories checkit's monitoring needs and describes how each
maps to the new architecture: per-node Prometheus DaemonSets with remote_write
to a central query/storage backend.

---

## Current checkit monitoring inventory

### Prometheus instances

| Instance | Cluster | Retention | Replicas | Remote write |
|---|---|---|---|---|
| now | cluster-g2 | default (2h) | patched via scale | Mimir at mimir-distributor.mimir:8080 |
| now | cluster-sites0 | 7 days | 1 | Mimir (commented out) |
| autoscale-v1 | cluster-g2 | 11min | 2 | None |

The `now` instance on cluster-g2 has substantial resource requests (CPU: 1, Memory: 11500Mi)
and uses external labels `cluster: g2, region: europe-west4`.

### PodMonitor CRDs (~51 files)

These are the scrape targets that must be migrated to either annotation-based
discovery or explicit scrape_configs:

**Infrastructure monitoring:**
- node-exporter (from ystack)
- loki (`cluster-g2/logs/loki-podmonitor.yaml`)
- keda-operator (`autoscale-v1/keda/keda-operator-podmonitor.yaml`)

**Application workloads (per service):**
- events-v1 (ports: http, api; path: /q/metrics)
- keycloak-v3 (path: /metrics)
- analytics-v3
- gateway-v3 (path: /stats/prometheus, envoy metrics)
- gateway-v4
- stats-v2
- outside-v1
- rest-v1
- autoscale-v1/prometheus (self-monitoring)

**Site-chart templated PodMonitors** (deployed per site):
- slashmetricshttp - generic /metrics scraper
- singlequarkus - Quarkus app metrics at /q/metrics
- singleenvoy - Envoy sidecar metrics at /stats/prometheus

### ServiceMonitor CRDs

- Kafka JMX (`monitoring/kafka-servicemonitor.yaml`) - port 5556, 120s interval
- Redpanda (`autoscale-v1/prometheus/redpanda-servicemonitor.yaml`)
- kminion (`kafka-v2/cluster-backend/kminion-servicemonitor.yaml`)

### PrometheusRule CRDs

**Kubernetes-scoped rules** (10 files in `monitoring/yolean-rules-k8s/`):
- ContainerCPUThrottled
- PodOOMKilledRiskDetected
- TargetDown, NodeExporterTargetDown
- KubeContainerStuck, KubeContainerStuckInitializing, KubePodStuckPending
- Pod unavailability, volume usage, job failure, termination alerts

**Custom application rules** (29 files in `monitoring/yolean-rules-custom/`):
- Kafka lag alerts (multiple versions)
- Live-v3 alerts (30+ rules: query failures, consumer lag, etc.)
- Notification delivery alerts
- Keycloak errors
- Events errors
- KKV cache errors
- Outside-v1, REST-v1, integrations, opindex, prints, showcases alerts
- Memcached, MySQL cluster, user cache alerts
- CPU usage alerts, boards errors

**Kubernetes-mixin rules** (`monitoring/k8s-alerts/`):
- Standard kubernetes-mixin recording rules and alerts
- Prometheus-operator alerts (will be removed)
- KubePersistentVolumeErrors
- CPUThrottlingHigh override (severity: warning)

### Alertmanager configuration

Receivers:
- **OpsGenie** (EU API) for production alerts
- **iLert** webhook
- **Internal webhook** to `alerts-hook` (Quarkus app -> Kafka topic `alerts.stream.json.001`)
- **null** for suppressed alerts

Routing: Groups by job, 1h repeat for OpsGenie, dev-site specific suppression,
warning severity suppressed.

### Remote write to Mimir

Current config (`now-prometheus-write-mimir.yaml`):
- Endpoint: `http://mimir-distributor.mimir.svc.cluster.local:8080/api/v1/push`
- Filtered to specific metrics (ALERTS, live_*, broker_*, boards_*, kkv_*,
  envoy_*, keda_*, container_network_*, redpanda_*, kube_pod_status_*, etc.)
- Queue capacity: 10 (limited)

### Grafana datasources

- Prometheus now (ystack base)
- Mimir (`mimir-query-frontend.mimir:8080/prometheus`)
- GCP Managed Prometheus (`frontend.monitoring-gmp:9090`)
- Loki (`loki-read-headless.logs:3100`)
- ClickHouse (bi-v1, port 9000)

---

## Migration mapping

### Phase 1: PodMonitor/ServiceMonitor -> annotations + scrape_configs

**Annotation-based (majority of workloads):**

Most PodMonitors can be replaced by adding `prometheus.io/scrape: "true"` annotations
to the pod templates. The generic `kubernetes-pods` scrape job in the Prometheus config
handles these automatically.

For workloads already using `/metrics` on their default port, only one annotation is needed.
For non-standard paths or ports:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"       # if not the default pod port
  prometheus.io/path: "/q/metrics"  # if not /metrics
```

Workloads needing annotations:
- events-v1: path=/q/metrics, port=8080
- keycloak-v3: path=/metrics (standard)
- gateway-v3/v4: path=/stats/prometheus (envoy)
- All Quarkus apps: path=/q/metrics
- alerts-hook: already has prometheus.io annotations

**Explicit scrape_configs (complex cases):**

These need dedicated scrape_config blocks because they have custom relabeling,
non-standard intervals, or cross-namespace discovery:

1. **Kafka JMX** (120s interval, 119s timeout, specific port 5556, RBAC in kafka namespace)
2. **Redpanda** (custom metric_relabel_configs)
3. **kminion** (Kafka consumer metrics)

These go into the Prometheus ConfigMap as additional `scrape_configs` entries.

**Site-chart templated PodMonitors:**

The site-chart templates (slashmetricshttp, singlequarkus, singleenvoy) currently
generate PodMonitor CRDs per site. These must be converted to:
- Add `prometheus.io/scrape: "true"` annotations to the pod templates in the site chart
- For envoy sidecars (path=/stats/prometheus), add `prometheus.io/path` annotation
- Remove the PodMonitor templates from the chart

### Phase 2: PrometheusRule -> plain rule files

All PrometheusRule CRDs become plain YAML files mounted in the Prometheus ConfigMap:

```
monitoring/prometheus-now/rules/
  node-exporter.yml          # from ystack
  kubernetes-mixin.yml       # from monitoring/k8s-alerts/
  yolean-k8s.yml            # from monitoring/yolean-rules-k8s/
  yolean-custom.yml          # from monitoring/yolean-rules-custom/
  gateway-alerts.yml         # from gateway-v4/cluster-backend-monitoring/
  keycloak-alerts.yml        # from keycloak-v3/cluster-backend-monitoring/
  rest-v1-alerts.yml         # from rest-v1/cluster-backend-monitoring/
  redpanda-alerts.yml        # from kafka-v3/cluster-backend-monitoring/
  keda-alerts.yml            # from autoscale-v1/keda-monitoring/
  cert-manager-alerts.yml    # from cluster-g2/cert-manager/alerts/
```

The content is identical - only the outer CRD wrapper is removed. The `groups:` key
and all recording/alerting rules within stay the same.

### Phase 3: Prometheus CRD -> DaemonSet + ConfigMap

Replace the operator-managed Prometheus with a DaemonSet that scrapes only local pods.

Key difference from ystack's single Deployment: in production, each node runs its own
Prometheus that only scrapes pods scheduled on that node. This is achieved via
the `__meta_kubernetes_pod_node_name` label in relabel_configs:

```yaml
relabel_configs:
  - source_labels: [__meta_kubernetes_pod_node_name]
    regex: $(NODE_NAME)
    action: keep
```

Where `$(NODE_NAME)` is expanded from the downward API env var. Prometheus v3 expands
environment variables in config by default (`expand-external-labels` is now always on,
and `$NODE_NAME` / `${NODE_NAME}` in scrape configs works natively).

Each Prometheus pod does `remote_write` to the central backend (Thanos or GreptimeDB).

### Phase 4: Alertmanager CRD -> Deployment

The Alertmanager CRD becomes a plain Deployment (or StatefulSet for HA with 2 replicas).
The alertmanager.yaml secret with OpsGenie/iLert/internal routing stays unchanged.

### Phase 5: Prometheus autoscale-v1 instance

The separate autoscale-v1 Prometheus (11min retention, 5s scrape interval) needs evaluation:
- If its targets can be included in the main DaemonSet scrape (with different scrape interval),
  fold it into the main config with a separate scrape job
- If it must remain separate (5s scrape interval at scale), keep it as a standalone
  Deployment (not DaemonSet) since it only needs to monitor specific autoscaling pods

### Phase 6: Update Grafana datasources

- Prometheus "now" datasource URL stays the same if a query frontend preserves the service name
- Mimir datasource: either keep Mimir as a migration step, or replace with Thanos Query / GreptimeDB
- GMP datasource: independent, no change needed

---

## Production architecture: per-node Prometheus with central query

```
┌─────────────────────────────────────────────────┐
│  Zone A                                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐      │
│  │ Node 1   │  │ Node 2   │  │ Node 3   │      │
│  │ Prom DS  │  │ Prom DS  │  │ Prom DS  │      │
│  │ (local   │  │ (local   │  │ (local   │      │
│  │  scrape) │  │  scrape) │  │  scrape) │      │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘      │
│       │              │              │             │
│       └──────────────┼──────────────┘             │
│                      ▼                            │
│              ┌──────────────┐                     │
│              │ Write endpoint│ (zone-local)       │
│              │ (Thanos Recv │                     │
│              │  or GrepTime)│                     │
│              └──────┬───────┘                     │
│                     │                             │
└─────────────────────┼─────────────────────────────┘
                      │ upload blocks / write to
                      ▼
               ┌──────────────┐
               │   GCS bucket │ (shared across zones)
               └──────┬───────┘
                      │
                      ▼
               ┌──────────────┐
               │ Query UI     │ (can cross zones)
               │ + Store GW   │
               └──────────────┘
                      │
                      ▼
               ┌──────────────┐
               │   Grafana    │
               └──────────────┘
```

---

## Thanos vs GreptimeDB for the central backend

### Requirements summary

1. Accept Prometheus `remote_write` from per-node DaemonSet instances
2. Provide Prometheus-compatible query UI
3. Store long-term metrics in GCS
4. **Avoid inter-zone traffic for metric writes** (querying can cross zones)
5. Replace current Mimir remote_write destination

### Comparison

| Criterion | Thanos Receive | GreptimeDB |
|---|---|---|
| **Zone-aware writes** | Native AZ-aware hashring (built-in since v0.32). Deploy one Receive per zone, RF=1, zero cross-zone write traffic. | No built-in zone routing. Achieve via one standalone instance per zone + shared GCS bucket. Manual topology. |
| **Write endpoint** | `/api/v1/receive` | `/v1/prometheus/write` |
| **Query UI** | Prometheus-derivative UI built in (Thanos Query). 100% PromQL via actual Prometheus engine. | Custom dashboard UI + PromQL endpoint. ~90% PromQL compatibility (reimplemented in Rust). |
| **GCS storage** | Native. TSDB blocks uploaded every 2h by Receive, queried via Store Gateway. | Native via OpenDAL. Parquet files, better compression. |
| **Deployment (minimal)** | 5-6 components, 11-12 pods HA: Receive (3), Query (2), Store GW (1-2), Compactor (1), optionally Query Frontend (2) | Standalone: 1 pod per zone. Distributed: 4 components, 11+ pods (comparable to Thanos). |
| **Resources (3-10 nodes)** | ~3-6 CPU, 5-12 GiB total | Standalone: 1-2 CPU, 2-4 GiB per instance |
| **PromQL compatibility** | 100% (uses Prometheus engine) | >90% (some edge cases documented) |
| **Maturity** | Since 2017, CNCF Incubating. Production at Alibaba, Red Hat OpenShift, Monzo, Wikimedia, Zapier. | Since 2022, pre-GA (v1.0 beta Nov 2025, GA target Jan 2026). Fewer production references. |
| **License** | Apache 2.0 | Apache 2.0 |
| **Grafana integration** | Standard Prometheus datasource | Prometheus-compatible datasource (works, may need adjustments for complex queries) |
| **Alerting** | Thanos Rule component can evaluate rules on global view. Or keep per-node alerting. | No built-in alert evaluation. Alerts must stay in per-node Prometheus. |
| **Downsampling** | Built-in via Compactor (5m, 1h automatic) | Manual via continuous aggregation (Flow) |

### Zone-aware write patterns in detail

**Thanos Receive (recommended approach):**

Deploy one Thanos Receive Ingestor StatefulSet per zone. Each Prometheus
DaemonSet pod writes to a zone-local Kubernetes Service:

```yaml
# Per-zone service with topology routing
apiVersion: v1
kind: Service
metadata:
  name: thanos-receive
  annotations:
    service.kubernetes.io/topology-mode: Auto
spec:
  selector:
    app: thanos-receive
  ports:
    - name: remote-write
      port: 19291
```

With `topology-mode: Auto`, kube-proxy routes to the closest endpoint (same zone).
Alternatively, deploy separate Services per zone.

Set replication factor to 1 (`--receive.replication-factor=1`). Durability comes
from the 2h block upload to GCS, not from in-memory replication. This eliminates
all cross-zone write traffic.

Thanos Query fans out to all Receive instances and Store Gateways at query time,
which is acceptable (queries cross zones, per the requirement).

```
remote_write:
  - url: http://thanos-receive.monitoring:19291/api/v1/receive
```

**GreptimeDB (alternative approach):**

Deploy one GreptimeDB standalone instance per zone, all writing to the same
GCS bucket with different storage prefixes:

```
remote_write:
  - url: http://greptimedb-zone-a.monitoring:4000/v1/prometheus/write
```

Querying requires either:
- A GreptimeDB instance configured to read all zone prefixes from GCS
- Grafana configured with multiple datasources (one per zone) and mixed queries
- A frontend proxy that fans out to all instances

This works but is less integrated than Thanos's native multi-instance querying.

### Recommendation

**Thanos Receive** is the stronger choice for this use case:

1. **Zone-aware writes are a first-class feature**, not a workaround
2. **100% PromQL compatibility** avoids dashboard migration issues (checkit has complex alert rules)
3. **Thanos Rule** can evaluate alerting rules against the global dataset, which matters for
   cross-node alerts (e.g., "cluster has fewer than N ready pods")
4. **Battle-tested** at organizations with similar scale
5. **Grafana datasource** is a standard Prometheus datasource, zero changes to existing dashboards

The operational complexity (5-6 components) is the main cost. For a production cluster
already running Mimir (which has similar component count), this is comparable.

**GreptimeDB** remains interesting for future evaluation. Its standalone mode (1 pod)
is compelling for simpler clusters, and Parquet storage costs could be significantly lower.
Consider revisiting after GreptimeDB reaches GA (expected Jan 2026) and PromQL
compatibility reaches 100%.

### Migration path from current Mimir

The current Mimir remote_write config in checkit can be switched to Thanos Receive
with minimal changes:

```yaml
# Current (Mimir):
remote_write:
  - url: http://mimir-distributor.mimir.svc.cluster.local:8080/api/v1/push

# New (Thanos Receive):
remote_write:
  - url: http://thanos-receive.monitoring.svc.cluster.local:19291/api/v1/receive
```

The `writeRelabelConfigs` with metric filtering can stay (or be relaxed, since
per-node Prometheus with 2h retention reduces the write volume naturally).

Grafana datasource change:

```yaml
# Current (Mimir):
url: http://mimir-query-frontend.mimir.svc.cluster.local:8080/prometheus

# New (Thanos Query):
url: http://thanos-query.monitoring.svc.cluster.local:9090
```

---

## Implementation order for checkit

1. **Merge ystack `local-cluster-provision-alignment`** - prerequisite
2. **Apply ystack vanilla prometheus migration** - per `ystack-vanilla-prometheus.md`
3. **Deploy Thanos Receive + Query + Store GW + Compactor** in monitoring namespace
4. **Convert checkit PodMonitors to annotations** - start with workloads that already
   have `prometheus.io/scrape` annotations, then add to remaining workloads
5. **Convert PrometheusRules to plain rule files** - extract `spec.groups` from each CRD
6. **Convert ServiceMonitors to explicit scrape_configs** - Kafka JMX, Redpanda, kminion
7. **Switch Prometheus from operator CRD to DaemonSet** - per-node scraping with
   remote_write to Thanos Receive
8. **Switch Grafana datasource** from Mimir to Thanos Query
9. **Remove prometheus-operator** from cluster-g2 and cluster-sites0
10. **Decommission Mimir** once Thanos is validated
