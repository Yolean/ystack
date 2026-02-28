# Research: Replacing Mimir with S3/GCS-based metrics storage

## Context

This document follows the [metrics-v2 plan](metrics-v2-plan.md) which replaces prometheus-operator with plain Kubernetes resources. The next question is whether we can also replace Mimir — a distributed, multi-component system (distributor, ingester, compactor, store-gateway, querier, query-frontend) — with something simpler.

### Current Mimir setup

- **Deployment**: `cluster-g2/mimir/` — based on `Yolean/unhelm/mimir/mimir-distributed`
- **Image**: `grafana/mimir:2.2.0`
- **Components**: distributor (3 replicas), ingester, compactor, store-gateway, querier, query-frontend, ruler (disabled)
- **Storage**: GCS bucket `yo-g2-monitoring-mimir-001` in `europe-west4`
- **PVCs**: 3x 10Gi `premium-rwo` (compactor, ingester, store-gateway)
- **Topology**: Spread constraints across evictable nodes
- **Querying**: Grafana datasource at `http://mimir-query-frontend.mimir.svc.cluster.local:8080/prometheus` (Prometheus-compatible API)
- **Federation**: `mimir-distributor.svc.yolean.se` via external DNS for cross-cluster writes (cluster-sites0 writes to this endpoint)
- **Multi-tenancy**: Disabled
- **Retention/limits**: Unlimited series, unlimited ingestion rate

### Inspiration: logs/nodes-to-gcs pattern

The existing `logs/nodes-to-gcs` architecture provides a proven pattern:
1. **DaemonSet** collects data per node (FluentBit tailing pod logs)
2. **Ships to GCS** in columnar format (Parquet/Arrow) via S3-compatible API with HMAC keys
3. **Path-based partitioning**: `/{cluster}/{namespace}/{Y}/{M}/{D}/{node}/{pod}/{container}/{H}/{M}/{uuid}.parquet`
4. **Event-driven processing**: GCS OBJECT_FINALIZE → Pub/Sub → consumer (logs-server with DuckDB)
5. **Config reload**: Kustomize hash-suffixed secrets/configmaps

The question: can we apply this pattern to metrics?

---

## Alternatives evaluated

### Alternative A: Thanos Sidecar + Store Gateway

**Architecture**: Add a Thanos sidecar container to each Prometheus DaemonSet pod. The sidecar uploads TSDB blocks (every 2h) to GCS. A Thanos Query deployment provides a unified Prometheus UI across all nodes and historical data.

```
Prometheus DaemonSet pod (per node)
├── prometheus container (scrapes local pods)
└── thanos-sidecar container
    ├── serves StoreAPI on gRPC :10901
    └── uploads TSDB blocks to GCS every 2h

Thanos Query (Deployment, 1-2 replicas)
├── queries all sidecars via StoreAPI
├── queries Thanos Store Gateway for historical data
└── serves Prometheus-compatible UI + API

Thanos Store Gateway (StatefulSet, 1 replica)
├── reads TSDB blocks from GCS
└── serves historical data via StoreAPI

Thanos Compactor (StatefulSet, 1 replica)
├── compacts + downsamples blocks in GCS
└── manages retention
```

**Pros**:
- CNCF Incubating project, very mature
- Native TSDB block format — no format conversion, no data loss
- Thanos Query provides a real Prometheus UI with full PromQL across all nodes + history
- Deduplication built-in (handles DaemonSet replicas cleanly via `__replica__` label)
- Grafana can query Thanos Query as a Prometheus datasource (drop-in for current Mimir datasource)
- Cross-cluster federation via Thanos Query connecting to remote sidecars/stores
- Retention policy in Compactor (configurable per-resolution)
- Prometheus instances stay fully independent — sidecar is read-only

**Cons**:
- 4 additional components (sidecar, query, store-gateway, compactor)
- Sidecar requires `--storage.tsdb.min-block-duration=2h --storage.tsdb.max-block-duration=2h` on Prometheus (disables local compaction)
- 2h upload granularity — recent data (0-2h) only available from live Prometheus instances via sidecar StoreAPI
- Store Gateway needs a PVC for block index caching
- Still a distributed system, just simpler than Mimir

**GCS config for sidecar** (example):
```yaml
type: GCS
config:
  bucket: yo-g2-monitoring-metrics-v2
```

**Estimated resource overhead**: ~200Mi per sidecar, ~512Mi for store-gateway, ~256Mi for query, ~512Mi for compactor.

---

### Alternative B: Thanos Receive (replaces remote_write target)

**Architecture**: Instead of a sidecar, use Thanos Receive as the remote_write endpoint. Prometheus DaemonSet pods remote-write to Thanos Receive, which stores to local TSDB and uploads blocks to GCS.

```
Prometheus DaemonSet (per node)
└── remote_write → Thanos Receive

Thanos Receive (StatefulSet, 1-2 replicas)
├── accepts remote_write
├── local TSDB storage
└── uploads blocks to GCS every 2h

Thanos Query + Store Gateway + Compactor (same as Alt A)
```

**Pros**:
- No sidecar needed — Prometheus stays unmodified
- Acts as a drop-in replacement for Mimir's distributor+ingester
- Same query stack as Alternative A

**Cons**:
- Receive is the single ingestion point (like Mimir distributor) — defeats the DaemonSet decentralization
- Requires its own PVC and HA configuration (hashring)
- Essentially rebuilds a simpler Mimir — still a stateful distributed ingest path
- More complex than sidecar for our use case (DaemonSet already has local TSDB)

**Verdict**: Not recommended. If we're moving away from Mimir's centralized ingestion, adding another centralized receiver doesn't help.

---

### Alternative C: prom2parquet / prom-store-s3 (Parquet to GCS)

**Architecture**: Use a lightweight remote_write receiver that writes Prometheus metrics as Parquet files to GCS, mirroring the logs/nodes-to-gcs pattern exactly.

```
Prometheus DaemonSet (per node)
└── remote_write → prom2parquet (sidecar or separate deployment)
    └── writes .parquet files to GCS

Query layer: ???
```

**Relevant projects**:
- [prom2parquet](https://github.com/acrlabs/prom2parquet) — Alpha, 9 stars, 27 commits. Writes Parquet to local or S3. No query support.
- [prom-store-s3](https://github.com/floj/prom-store-s3) — Experimental, self-described as "vibe-coded". Supports remote_write AND remote_read to S3 as Parquet. Not production-ready.
- [prometheus-community/parquet-common](https://github.com/prometheus-community/parquet-common) — Official prometheus-community Go library for TSDB↔Parquet conversion. Early development, breaking changes expected. Implements `storage.Queryable` interface.

**Pros**:
- Closest match to the logs/nodes-to-gcs pattern (Parquet files in GCS buckets)
- Could reuse HMAC credential pattern, setup scripts, GCS notification flow
- Parquet is queryable from DuckDB, Spark, Jupyter — familiar from logs pipeline
- prometheus-community/parquet-common suggests this is a direction the Prometheus project is exploring

**Cons**:
- No production-ready implementation exists today
- No Prometheus UI / PromQL query layer for Parquet-stored metrics (the prometheus-community library is the closest, but early-stage)
- Would need to build: a query adapter that reads Parquet from GCS and serves PromQL
- Format conversion overhead (TSDB → Parquet on every write)
- Loses TSDB block semantics (compaction, downsampling)

**Verdict**: Interesting future direction, but not viable today. The prometheus-community/parquet-common library is worth watching — when it matures, it could enable a "Prometheus reads Parquet from GCS" workflow. Today, the tooling gap is too large.

---

### Alternative D: GreptimeDB

**Architecture**: GreptimeDB as a Prometheus-compatible remote storage that natively stores data as Parquet files in GCS.

```
Prometheus DaemonSet (per node)
├── remote_write → GreptimeDB /api/v1/prom/remote/write
└── (optional) remote_read ← GreptimeDB /api/v1/prom/remote/read

GreptimeDB (StatefulSet or Operator-managed)
├── ingests via remote_write
├── stores as Parquet in GCS
├── serves PromQL queries
└── optional: Loki protocol, OpenTelemetry traces
```

**Pros**:
- Native Parquet storage on GCS/S3 — aligns with the logs/nodes-to-gcs philosophy
- Full PromQL compatibility (serves as Prometheus-compatible datasource for Grafana)
- Supports both remote_write and remote_read — Prometheus UI can query historical data
- Single binary / Operator deployment, simpler than Mimir's 6+ components
- Reports 3-5x cost reduction vs block storage (Parquet compression + object storage pricing)
- Multi-signal: could also handle logs (Loki protocol) and traces (OpenTelemetry) — potential convergence

**Cons**:
- Younger project — less battle-tested than Thanos/Mimir
- Introduces a new CRD (GreptimeDBCluster) via its Operator — we're trying to reduce CRD dependencies
- Standalone mode (no CRD) is possible but less documented for production
- Still a stateful service that needs its own PVC for write-ahead log + SSD cache
- Cross-cluster federation would need separate configuration

**Verdict**: Promising if we want Parquet-native storage with PromQL. Worth a PoC, but the maturity gap vs Thanos is significant.

---

### Alternative E: VictoriaMetrics single-node

**Architecture**: Replace Mimir with a single VictoriaMetrics instance receiving remote_write.

```
Prometheus DaemonSet (per node)
└── remote_write → VictoriaMetrics

VictoriaMetrics (StatefulSet, 1 replica)
├── receives remote_write
├── stores on block storage (PVC)
├── serves PromQL-compatible queries
└── vmbackup → GCS (periodic snapshots)
```

**Pros**:
- Extremely simple — single binary, single PVC
- 20x better compression than Prometheus TSDB
- Full PromQL compatibility, serves as Grafana datasource
- vmbackup/vmrestore for GCS/S3 snapshots (incremental, from live instance)
- Very low resource usage compared to Mimir

**Cons**:
- Does NOT store data in object storage natively — uses block storage (PVC), GCS only for backups
- Not a direct replacement for the "cheap object storage for unlimited retention" model
- Single point of failure (though vmbackup provides disaster recovery)
- Cluster mode (for HA) is enterprise-only feature in newer versions

**Verdict**: Good simplification over Mimir if block storage cost is acceptable. Doesn't match the GCS-native pattern we're looking for, but worth considering as the pragmatic middle ground.

---

### Alternative F: FluentBit for metrics shipping

**Architecture**: Use FluentBit (already deployed for logs) to also scrape and ship Prometheus metrics to GCS.

FluentBit has:
- `prometheus_scrape_metrics` input plugin — scrapes Prometheus endpoints
- `s3` output plugin — writes to S3/GCS (Parquet support)
- `prometheus_remote_write` output plugin — forwards as remote_write

```
FluentBit DaemonSet (per node, already deployed)
├── INPUT: prometheus_scrape_metrics (scrape local pods)
├── OUTPUT: s3 (write to GCS as Parquet)
└── (or) OUTPUT: prometheus_remote_write (forward to a query backend)
```

**Pros**:
- Reuses existing infrastructure (FluentBit DaemonSet already runs for logs)
- Could unify logs + metrics collection into one DaemonSet
- GCS output path and credentials pattern already established

**Cons**:
- FluentBit's Prometheus scrape input is basic — no `kubernetes_sd_configs` equivalent, no relabeling
- Would need to configure each scrape target explicitly or use a sidecar for discovery
- No PromQL query layer — Parquet files in GCS need a separate query engine
- Metrics have different semantics than logs (time series with labels vs text lines) — Parquet schema would differ
- FluentBit doesn't understand Prometheus exposition format nuances (histograms, summaries, staleness markers)
- Loses all Prometheus evaluation (recording rules, alerting rules can't run on FluentBit)

**Verdict**: Not suitable. FluentBit is excellent for log forwarding but lacks the service discovery, PromQL evaluation, and time series semantics needed for metrics. You'd still need Prometheus for scraping and alerting, making FluentBit redundant in the metrics path.

---

## Comparison matrix

| Criterion | A: Thanos Sidecar | B: Thanos Receive | C: Parquet direct | D: GreptimeDB | E: VictoriaMetrics | F: FluentBit |
|---|---|---|---|---|---|---|
| Storage backend | GCS (TSDB blocks) | GCS (TSDB blocks) | GCS (Parquet) | GCS (Parquet) | PVC + GCS backup | GCS (Parquet) |
| PromQL query | Full (Thanos Query) | Full (Thanos Query) | None today | Full (native) | Full (native) | None |
| Prometheus UI | Yes (via Thanos Query) | Yes (via Thanos Query) | No | Via remote_read | As Grafana datasource | No |
| Production maturity | High (CNCF) | High (CNCF) | Alpha/experimental | Medium | High | N/A for metrics |
| Components to deploy | sidecar + query + store-gw + compactor | receive + query + store-gw + compactor | custom adapter | 1 (standalone) or operator | 1 (single-node) | 0 extra (reuse existing) |
| Cross-cluster query | Yes (native) | Yes (native) | No | Manual config | No (single-node) | No |
| Matches logs/GCS pattern | Partially (GCS, not Parquet) | Partially | Yes | Yes (Parquet on GCS) | No | Yes |
| Deduplication | Built-in | Built-in | Manual | Unknown | Built-in | N/A |
| Replaces Mimir cleanly | Yes | Yes | No (no query) | Yes | Mostly (PVC not GCS) | No |
| Alerting rules | Thanos Ruler or Prometheus | Same | Prometheus only | GreptimeDB + Prometheus | Prometheus only | No |

## Evaluation plan: Thanos vs GreptimeDB head-to-head

Both Thanos (Alternative A) and GreptimeDB (Alternative D) are viable Mimir replacements that store data in GCS. We will deploy both in parallel against the metrics-v2 stack and select the one that's operationally cheapest — fewest components, lowest resource usage, least maintenance burden.

### Phase 1: Deploy both candidates (week 1)

Both receive the same data: the metrics-v2 Prometheus DaemonSet sends remote_write to GreptimeDB and uses Thanos sidecar for block uploads simultaneously. This dual-write period lets us compare with identical input.

#### 1a. Thanos deployment in `metrics-v2`

Add to the Prometheus DaemonSet pod spec:

```yaml
# thanos-sidecar container (added to prometheus DaemonSet)
- name: thanos-sidecar
  image: quay.io/thanos/thanos:v0.37.2
  args:
  - sidecar
  - --tsdb.path=/prometheus
  - --prometheus.url=http://localhost:9090
  - --objstore.config-file=/etc/thanos/bucket.yaml
  - --grpc-address=0.0.0.0:10901
  ports:
  - name: grpc
    containerPort: 10901
  volumeMounts:
  - name: data
    mountPath: /prometheus
  - name: thanos-bucket-config
    mountPath: /etc/thanos
    readOnly: true
```

Prometheus flags must be set:
```
--storage.tsdb.min-block-duration=2h
--storage.tsdb.max-block-duration=2h
```

Deploy these additional resources:

```yaml
# Headless service for sidecar gRPC discovery
apiVersion: v1
kind: Service
metadata:
  name: prometheus-sidecar
  namespace: metrics-v2
spec:
  clusterIP: None
  ports:
  - name: grpc
    port: 10901
  selector:
    app: prometheus
---
# Thanos Query — unified Prometheus UI across all DaemonSet pods
apiVersion: apps/v1
kind: Deployment
metadata:
  name: thanos-query
  namespace: metrics-v2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: thanos-query
  template:
    metadata:
      labels:
        app: thanos-query
    spec:
      containers:
      - name: thanos-query
        image: quay.io/thanos/thanos:v0.37.2
        args:
        - query
        - --endpoint=dnssrv+_grpc._tcp.prometheus-sidecar.metrics-v2.svc.cluster.local
        - --endpoint=dnssrv+_grpc._tcp.thanos-store-gateway.metrics-v2.svc.cluster.local
        - --query.replica-label=__replica__
        ports:
        - name: http
          containerPort: 9090
        - name: grpc
          containerPort: 10901
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: thanos-query
  namespace: metrics-v2
spec:
  ports:
  - name: http
    port: 9090
  - name: grpc
    port: 10901
  selector:
    app: thanos-query
---
# Thanos Store Gateway — serves historical blocks from GCS
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: thanos-store-gateway
  namespace: metrics-v2
spec:
  serviceName: thanos-store-gateway
  replicas: 1
  selector:
    matchLabels:
      app: thanos-store-gateway
  template:
    metadata:
      labels:
        app: thanos-store-gateway
    spec:
      containers:
      - name: thanos-store
        image: quay.io/thanos/thanos:v0.37.2
        args:
        - store
        - --data-dir=/data
        - --objstore.config-file=/etc/thanos/bucket.yaml
        - --grpc-address=0.0.0.0:10901
        ports:
        - name: grpc
          containerPort: 10901
        - name: http
          containerPort: 10902
        resources:
          requests:
            cpu: 100m
            memory: 512Mi
        volumeMounts:
        - name: data
          mountPath: /data
        - name: thanos-bucket-config
          mountPath: /etc/thanos
          readOnly: true
      volumes:
      - name: thanos-bucket-config
        configMap:
          name: thanos-bucket-config
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ReadWriteOnce]
      resources:
        requests:
          storage: 5Gi
---
apiVersion: v1
kind: Service
metadata:
  name: thanos-store-gateway
  namespace: metrics-v2
spec:
  clusterIP: None
  ports:
  - name: grpc
    port: 10901
  - name: http
    port: 10902
  selector:
    app: thanos-store-gateway
---
# Thanos Compactor — compacts blocks in GCS, manages retention
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: thanos-compactor
  namespace: metrics-v2
spec:
  serviceName: thanos-compactor
  replicas: 1
  selector:
    matchLabels:
      app: thanos-compactor
  template:
    metadata:
      labels:
        app: thanos-compactor
    spec:
      containers:
      - name: thanos-compact
        image: quay.io/thanos/thanos:v0.37.2
        args:
        - compact
        - --data-dir=/data
        - --objstore.config-file=/etc/thanos/bucket.yaml
        - --wait
        - --retention.resolution-raw=30d
        - --retention.resolution-5m=90d
        - --retention.resolution-1h=365d
        - --deduplication.replica-label=__replica__
        ports:
        - name: http
          containerPort: 10902
        resources:
          requests:
            cpu: 100m
            memory: 512Mi
        volumeMounts:
        - name: data
          mountPath: /data
        - name: thanos-bucket-config
          mountPath: /etc/thanos
          readOnly: true
      volumes:
      - name: thanos-bucket-config
        configMap:
          name: thanos-bucket-config
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ReadWriteOnce]
      resources:
        requests:
          storage: 10Gi
```

GCS bucket config (shared configmap):
```yaml
# thanos-bucket-config ConfigMap
type: GCS
config:
  bucket: yo-g2-monitoring-thanos-eval
```

GCS bucket setup (following `logs/nodes-to-gcs/setup.sh` pattern):
```bash
BUCKET=yo-g2-monitoring-thanos-eval
REGION=europe-west4
PROJECT=yo-prod
gcloud storage buckets create gs://$BUCKET --location=$REGION --project=$PROJECT
# Thanos uses Application Default Credentials or Workload Identity — no HMAC keys needed
```

**Total new resources for Thanos**: sidecar container (in DaemonSet), 1 Deployment (query), 2 StatefulSets (store-gateway, compactor), 3 Services, 1 ConfigMap, 2 PVCs (5Gi + 10Gi).

#### 1b. GreptimeDB deployment in `metrics-v2`

```yaml
# GreptimeDB standalone — single StatefulSet, Parquet on GCS
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: greptimedb
  namespace: metrics-v2
spec:
  serviceName: greptimedb
  replicas: 1
  selector:
    matchLabels:
      app: greptimedb
  template:
    metadata:
      labels:
        app: greptimedb
    spec:
      containers:
      - name: greptimedb
        image: greptime/greptimedb:latest
        args:
        - standalone
        - start
        - --http-addr=0.0.0.0:4000
        - --rpc-addr=0.0.0.0:4001
        - --mysql-addr=0.0.0.0:4002
        env:
        - name: GREPTIMEDB_STANDALONE__STORAGE__TYPE
          value: Gcs
        - name: GREPTIMEDB_STANDALONE__STORAGE__BUCKET
          value: yo-g2-monitoring-greptimedb-eval
        - name: GREPTIMEDB_STANDALONE__STORAGE__ROOT
          value: data
        - name: GREPTIMEDB_STANDALONE__WAL__DIR
          value: /data/wal
        ports:
        - name: http
          containerPort: 4000
        - name: grpc
          containerPort: 4001
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
        volumeMounts:
        - name: data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ReadWriteOnce]
      resources:
        requests:
          storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: greptimedb
  namespace: metrics-v2
spec:
  ports:
  - name: http
    port: 4000
  - name: grpc
    port: 4001
  selector:
    app: greptimedb
```

Add to the Prometheus DaemonSet config (alongside existing remote_write to Mimir):
```yaml
remote_write:
- name: greptimedb-eval
  url: http://greptimedb.metrics-v2.svc.cluster.local:4000/v1/prometheus/write
  queue_config:
    capacity: 10
    retry_on_http_429: false
  # Same write_relabel_configs as the Mimir remote_write — only selected metrics
```

GCS bucket setup:
```bash
BUCKET=yo-g2-monitoring-greptimedb-eval
REGION=europe-west4
PROJECT=yo-prod
gcloud storage buckets create gs://$BUCKET --location=$REGION --project=$PROJECT
# GreptimeDB uses Workload Identity or GOOGLE_APPLICATION_CREDENTIALS
```

**Total new resources for GreptimeDB**: 1 StatefulSet, 1 Service, 1 PVC (10Gi), remote_write entry in prometheus config.

#### 1c. Grafana datasources for both

Add both as datasources so we can compare queries side by side:

```yaml
# datasources-thanos-eval.yaml
datasources:
- name: Thanos (eval)
  type: prometheus
  url: http://thanos-query.metrics-v2.svc.cluster.local:9090
  access: proxy

# datasources-greptimedb-eval.yaml
datasources:
- name: GreptimeDB (eval)
  type: prometheus
  url: http://greptimedb.metrics-v2.svc.cluster.local:4000/v1/prometheus
  access: proxy
```

### Phase 2: Measure and compare (weeks 2-3)

Run both for at least 2 weeks to accumulate enough data for meaningful comparison. Measure:

#### 2a. Operational complexity scorecard

| Question | Thanos | GreptimeDB |
|---|---|---|
| How many pods running? | Count all thanos-* + sidecar containers | Count greptimedb pods |
| How many PVCs? | store-gateway + compactor | greptimedb WAL/cache |
| Any crash loops or restarts during eval? | Check `kubectl get events` | Same |
| Config files to maintain? | bucket.yaml + query endpoints | storage env vars + remote_write URL |
| Does it need its own RBAC/ServiceAccount? | No (sidecar shares prometheus SA) | No |
| Upgrade path clear? | Single image tag for all components | Single image tag |
| Documentation quality for our use case? | Rate 1-5 | Rate 1-5 |

#### 2b. Resource usage

Collect over 2 weeks using existing kube-state-metrics + cadvisor:

```promql
# Total memory per candidate
sum(container_memory_working_set_bytes{namespace="metrics-v2", pod=~"thanos-.*"})
sum(container_memory_working_set_bytes{namespace="metrics-v2", pod=~"greptimedb-.*"})

# Include sidecar overhead for Thanos
sum(container_memory_working_set_bytes{namespace="metrics-v2", pod=~"prometheus-.*", container="thanos-sidecar"})

# CPU
sum(rate(container_cpu_usage_seconds_total{namespace="metrics-v2", pod=~"thanos-.*"}[5m]))
sum(rate(container_cpu_usage_seconds_total{namespace="metrics-v2", pod=~"greptimedb-.*"}[5m]))

# PVC usage
kubelet_volume_stats_used_bytes{namespace="metrics-v2", persistentvolumeclaim=~".*thanos.*|.*greptimedb.*"}
```

#### 2c. GCS storage costs

```bash
# Check bucket sizes after 2 weeks
gsutil du -s gs://yo-g2-monitoring-thanos-eval
gsutil du -s gs://yo-g2-monitoring-greptimedb-eval

# Object count (fewer large objects = cheaper for GCS operations)
gsutil ls -r gs://yo-g2-monitoring-thanos-eval | wc -l
gsutil ls -r gs://yo-g2-monitoring-greptimedb-eval | wc -l
```

Both receive the same metrics via the same write_relabel_configs filter, so storage size is a direct comparison of format efficiency (TSDB blocks vs Parquet).

#### 2d. Query correctness and performance

Run the same queries against both and against Mimir (the baseline). Use every alert expression from the current PrometheusRules:

```bash
# For each alert expression, query all three backends and compare
# Example:
curl -s 'http://thanos-query:9090/api/v1/query?query=rate(envoy_cluster_upstream_cx_connect_timeout[1m])' | jq '.data.result | length'
curl -s 'http://greptimedb:4000/v1/prometheus/api/v1/query?query=rate(envoy_cluster_upstream_cx_connect_timeout[1m])' | jq '.data.result | length'
curl -s 'http://mimir-query-frontend:8080/prometheus/api/v1/query?query=rate(envoy_cluster_upstream_cx_connect_timeout[1m])' | jq '.data.result | length'
```

Key queries to validate:
1. All alert expressions from `metrics-v2/rules/*.yaml` (do they return the same series?)
2. Range queries: `rate(...[5m])` over 1h, 6h, 24h ranges
3. Aggregations: `sum by (namespace) (...)` — checks label preservation
4. Historical queries: query data from >2h ago (tests Thanos Store Gateway / GreptimeDB GCS reads)
5. Recording rules: verify `node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate` produces same values

#### 2e. Prometheus UI experience

For Thanos specifically — verify that `thanos-query:9090` provides a usable Prometheus UI:
- Can you browse targets? (Thanos Query doesn't show targets — only Prometheus instances do)
- Can you see active alerts? (Yes, if Thanos Query is configured with `--alert.query-url`)
- Is the query autocomplete responsive?
- Does the graph view work for range queries spanning local + historical data?

For GreptimeDB — it has no native Prometheus UI, but Prometheus can use `remote_read` to query it. Verify:
- Add `remote_read` config pointing at GreptimeDB
- Open any Prometheus DaemonSet pod's UI at `:9090` — does it transparently query historical data from GreptimeDB?
- Latency of remote_read queries vs local TSDB queries

#### 2f. Cross-cluster readiness

Document what's needed for cluster-sites0 to participate:
- **Thanos**: Add sidecar to sites0 Prometheus, add sites0 sidecar endpoint to Thanos Query `--endpoint` list (or use DNS federation)
- **GreptimeDB**: Add remote_write from sites0 Prometheus to the same GreptimeDB instance (already accessible via `mimir-distributor.svc.yolean.se` pattern)

### Phase 3: Score and decide (week 4)

#### Decision criteria (weighted)

| Criterion | Weight | How to score |
|---|---|---|
| Total pod count | 20% | Fewer pods = better. Count all pods including sidecars |
| Total memory requests | 15% | Lower = better. Sum all container memory requests |
| Total PVC count + size | 10% | Fewer/smaller = better |
| GCS storage cost (bytes/metric/day) | 15% | Lower = better. Normalize by ingested series count |
| Query correctness | 20% | Must match Mimir results exactly. Any discrepancy is disqualifying |
| Config/maintenance surface area | 10% | Fewer config files, fewer things to monitor |
| Maturity / community risk | 10% | CNCF status, GitHub activity, production adoption |

#### Scoring template

```
Candidate: ___________

Pod count:             ___ pods (including sidecar containers as 0.5)
Memory requests total: ___ Mi
PVC count/size:        ___ PVCs, ___Gi total
GCS bucket size (2wk): ___ GB
GCS object count:      ___
Query correctness:     ___/N alert expressions match Mimir
Query latency p50:     ___ ms (1h range query)
Query latency p99:     ___ ms (24h range query)
Config files:          ___ files to maintain
Crash/restart events:  ___ during eval period
Cross-cluster effort:  easy / moderate / hard

Total weighted score:  ___
```

#### Decision rules

1. If either candidate fails query correctness (alert expressions return different results than Mimir), it's disqualified
2. If both pass correctness, select the one with the lower weighted score (= operationally cheapest)
3. If scores are within 10%, prefer Thanos for maturity unless GreptimeDB shows a compelling storage cost advantage (>3x cheaper GCS)

### Phase 4: Implement winner (weeks 5-6)

1. Remove the losing candidate's resources from `metrics-v2`
2. Remove Mimir's remote_write from the Prometheus config (if Thanos wins, remote_write is eliminated entirely; if GreptimeDB wins, remote_write stays but points at GreptimeDB)
3. Update Grafana datasource: replace `Mimir` datasource URL with the winner's query endpoint
4. For Thanos: remove `remote_write` block from prometheus.yaml entirely — the sidecar handles data flow
5. For GreptimeDB: keep `remote_write` but remove the Mimir URL, point only at GreptimeDB
6. Validate all Grafana dashboards work with the new datasource
7. Scale down Mimir components to 0 replicas (keep PVCs for rollback)
8. After 1 week of stable operation, delete Mimir resources and GCS bucket

### Phase 5: Clean up (week 7)

1. Delete losing candidate's GCS bucket
2. Delete `cluster-g2/mimir/` directory
3. Remove Mimir datasource from `monitoring/grafana/datasources-mimir.yaml`
4. Remove `mimir-distributor-federation` service
5. Delete GCS bucket `yo-g2-monitoring-mimir-001` (after confirming no queries depend on historical data, or after migrating historical data to the winner)
6. Update `cluster-sites0` remote_write to point at the winner's ingest endpoint

---

## Architecture after evaluation (both possible outcomes)

### If Thanos wins

```
DaemonSet pod (per node):
  prometheus :9090       ← local scraping + alerting rules
  thanos-sidecar :10901  ← uploads TSDB blocks to GCS, serves StoreAPI

                ┌─────── gRPC StoreAPI ──────┐
                │                             │
                ▼                             ▼
        Thanos Query :9090          Thanos Store Gateway :10901
        (Deployment, 1-2 replicas)  (StatefulSet, 1 replica)
        ├── Prometheus UI               └── reads blocks from GCS
        └── Grafana datasource

        Thanos Compactor (StatefulSet, 1 replica)
        └── compacts + downsamples blocks in GCS

No remote_write. Data flows: Prometheus TSDB → sidecar → GCS → store gateway → query.
```

### If GreptimeDB wins

```
DaemonSet pod (per node):
  prometheus :9090
  └── remote_write → GreptimeDB

GreptimeDB (StatefulSet, 1 replica)
├── receives remote_write
├── stores as Parquet in GCS
├── Grafana datasource (PromQL-compatible)
└── Prometheus remote_read (optional, for Prometheus UI historical queries)
```

---

## Quick reference: what's cheaper about each

| | Thanos | GreptimeDB |
|---|---|---|
| **Eliminates remote_write** | Yes — sidecar reads TSDB directly | No — still needs remote_write path |
| **Pod count** | 3 extra pods + sidecar containers | 1 extra pod |
| **PVC count** | 2 (store-gw 5Gi + compactor 10Gi) | 1 (WAL/cache 10Gi) |
| **GCS format** | TSDB blocks (proven, compact) | Parquet (3-5x cheaper per GreptimeDB claims) |
| **Prometheus UI** | Full (Thanos Query) | Via remote_read only |
| **Community/maturity** | CNCF Incubating, years of production use | Younger, growing fast |
| **Config surface** | bucket.yaml + query endpoints | Storage env vars + remote_write URL |

### Long-term: Watch prometheus-community/parquet-common

The Prometheus community is actively developing Parquet support. When `prometheus-community/parquet-common` matures:
- Thanos could gain a Parquet storage backend (or a new store type could read Parquet from GCS)
- A "Prometheus Parquet Store Gateway" could replace Thanos Store Gateway, reading Parquet directly from GCS
- This would converge the metrics and logs storage formats, enabling unified tooling (DuckDB, Spark, etc.)

This is a 6-12 month horizon — not actionable today, but worth tracking.

## Sources

- [Thanos project](https://thanos.io/)
- [Thanos Sidecar component](https://thanos.io/tip/components/sidecar.md/)
- [Thanos Receive component](https://thanos.io/tip/components/receive.md/)
- [Thanos vs VictoriaMetrics comparison](https://last9.io/blog/thanos-vs-victoriametrics/)
- [Thanos vs VictoriaMetrics vs Mimir performance comparison](https://onidel.com/blog/prometheus-storage-comparison-2025)
- [VictoriaMetrics single-node docs](https://docs.victoriametrics.com/single-server-victoriametrics/)
- [VictoriaMetrics vmbackup](https://docs.victoriametrics.com/victoriametrics/vmbackup/)
- [GreptimeDB as Prometheus long-term storage](https://greptime.com/tech-content/2025-04-17-greptimedb-prometheus-comparison)
- [GreptimeDB Prometheus integration docs](https://docs.greptime.com/user-guide/ingest-data/for-observability/prometheus/)
- [prom2parquet](https://github.com/acrlabs/prom2parquet)
- [prometheus-community/parquet-common](https://github.com/prometheus-community/parquet-common)
- [prom-store-s3](https://github.com/floj/prom-store-s3)
- [FluentBit Prometheus remote write output](https://docs.fluentbit.io/manual/data-pipeline/outputs/prometheus-remote-write)
- [FluentBit Prometheus scrape input](https://docs.fluentbit.io/manual/data-pipeline/inputs/prometheus-scrape-metrics)
- [Prometheus 3.0 migration guide](https://prometheus.io/docs/prometheus/latest/migration/)
- [Prometheus storage documentation](https://prometheus.io/docs/prometheus/latest/storage/)
- [Best Prometheus alternatives 2026](https://www.dash0.com/comparisons/best-prometheus-alternatives)
