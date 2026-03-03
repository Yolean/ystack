# ystack metrics-v2 experiment — Results

Date: 2026-03-03
Branch: `metrics-v2-experiment`
Machine: macOS Darwin 23.6.0, x86_64, 16 GB RAM, 12 CPUs
Cluster: k3d ystack, k3s v1.35.1, `--memory=12G --docker-update="--cpus=8"`

## Deviations from plan

### 1. Prometheus config: `fallback_scrape_protocol` is not a global field

The vanilla prometheus plan specified `fallback_scrape_protocol: PrometheusText0.0.4`
as a global config option. Prometheus v3.10.0 rejected this — it's not a valid global
field. Replaced with `global.scrape_protocols` list instead:

```yaml
scrape_protocols:
  - OpenMetricsText1.0.0
  - OpenMetricsText0.0.1
  - PrometheusProto
  - PrometheusText1.0.0
  - PrometheusText0.0.4
```

### 2. Alertmanager version: v0.28.1 instead of v0.31.0

The plan specified Alertmanager v0.31.0. Used v0.28.1 instead because it was the
latest stable version available via the standard container registry at experiment time.
No functional impact — both use v2 API.

### 3. Monitoring directory consolidation

The plan assumed a single `k3s/30-monitoring/` directory. The actual codebase had the
monitoring split across `k3s/30-monitoring-operator/` and `k3s/31-monitoring/`. Created
a new `k3s/30-monitoring/` that merges both (minus the operator), leaving the old
directories in place for now.

### 4. Converge script: partial failure recovery

The converge script timed out on the first provision because of deviation #1. The
remaining steps (HTTPRoute, prod-registry, buildkit) were applied manually. The
converge script was updated to reflect the new structure.

### 5. Blob store: versitygw (not minio)

The plan referenced minio in some contexts. The codebase has already migrated to
versitygw. No changes needed for the experiment itself — Thanos Receive and GreptimeDB
both use emptyDir, not S3 object storage. Any future production deployment that uses
object storage for long-term retention must target the versitygw S3 API, not minio.

### 6. configmap-reload sidecar added

The plan did not mention configmap-reload, but it was added to the Prometheus
Deployment to enable live config/rules reloading without pod restarts. This is
necessary for the `--web.enable-lifecycle` reload endpoint to be triggered on
ConfigMap changes.

### 7. No `k3s/30-monitoring-operator` or `k3s/31-monitoring` removal

The old directories were left in place to avoid breaking any other branch that
references them. They can be removed once the migration is merged to main.

---

## Query comparison results

All queries run against Prometheus (source of truth), Thanos Query, and GreptimeDB.

### Test 1: Instant query `up`

| Backend | Target count | All UP? |
|---------|-------------|---------|
| Prometheus | 3 | Yes (node-exporter, kube-state-metrics, prometheus) |
| Thanos Query | 3 | Yes |
| GreptimeDB | 3 | Yes |

**Result: Identical**

### Test 2: Range query `rate(node_cpu_seconds_total{mode="idle"}[5m])`

| Backend | Series count | Values |
|---------|-------------|--------|
| Prometheus | 12 | cpu=0: 0.306213 ... cpu=11: 0.300287 |
| Thanos Query | 12 | cpu=0: 0.306671 ... cpu=11: 0.300737 |
| GreptimeDB | 12 | cpu=0: 0.306880 ... cpu=11: 0.300942 |

**Result: Consistent** — minor value differences (<0.3%) due to timestamp alignment
and sample boundaries. Same series count, same label sets.

### Test 3: Recording rule `instance:node_cpus:count`

| Backend | Result |
|---------|--------|
| Prometheus | k3d-ystack-server-0: 12 |
| Thanos Query | k3d-ystack-server-0: 12 |
| GreptimeDB | k3d-ystack-server-0: 12 |

**Result: Identical** — recording rules are evaluated by Prometheus and forwarded via
remote_write to both backends. Both return the correct value.

### Test 4: Alert expression `kube_pod_status_phase{phase="Pending"} > 0`

| Backend | Pending pods |
|---------|-------------|
| Prometheus | 0 |
| Thanos Query | 0 |
| GreptimeDB | 0 |

**Result: Identical** — no pending pods at query time.

### Test 5: Subquery `avg_over_time(instance:node_cpu_utilization:ratio[5m:])`

| Backend | Result |
|---------|--------|
| Prometheus | 0.106564 |
| Thanos Query | 0.109263 |
| GreptimeDB | 0.110593 |

**Result: Consistent** — all three support subquery syntax. Small value differences
from evaluation timing.

### PromQL incompatibilities observed in GreptimeDB

**None.** All tested queries returned correct results. GreptimeDB handled:
- Instant queries with label matchers
- Rate functions over counters
- Recording rule results (received via remote_write)
- Comparison operators (> 0)
- Subqueries (step-aligned range evaluation)

---

## Resource usage

Measured via `kubectl top pod` after ~5 minutes of dual remote_write operation.

| Component | CPU | Memory | Pod count |
|-----------|-----|--------|-----------|
| Prometheus (source) | 12m | 55Mi | 1 (2 containers) |
| Alertmanager | 3m | 18Mi | 1 |
| node-exporter | 4m | 9Mi | 1 |
| kube-state-metrics | 1m | 23Mi | 1 |
| **Thanos Receive** | **2m** | **37Mi** | **1** |
| **Thanos Query** | **2m** | **19Mi** | **1** |
| **GreptimeDB** | **19m** | **261Mi** | **1** |

### Summary

| Backend | Total CPU | Total Memory | Pod count |
|---------|-----------|-------------|-----------|
| Thanos (Receive + Query) | 4m | 56Mi | 2 |
| GreptimeDB (standalone) | 19m | 261Mi | 1 |

Thanos uses **4.75x less CPU** and **4.66x less memory** than GreptimeDB for the same
workload. GreptimeDB's standalone mode bundles storage engine + query engine + metadata
in a single process, which explains the higher baseline.

---

## Evaluation scores

Using the criteria from the Mimir replacement research.

### Query correctness (20%)

| Backend | Score | Notes |
|---------|-------|-------|
| Thanos | 10/10 | All queries identical to Prometheus |
| GreptimeDB | 10/10 | All queries returned correct results |

Both received full marks. In a larger test matrix with more complex PromQL (regex,
histogram_quantile, label_replace, etc.), GreptimeDB might show more divergence.

### Operational complexity (40%)

| Backend | Score | Notes |
|---------|-------|-------|
| Thanos | 7/10 | 2 components (Receive + Query), well-documented, CNCF graduated project. Would need Store + Compactor for production long-term storage. |
| GreptimeDB | 9/10 | 1 component in standalone mode, simpler topology. Distributed mode adds complexity (metasrv, datanode, frontend). |

GreptimeDB wins on simplicity for small deployments. Thanos has more operational
overhead but is battle-tested at scale.

### Resource usage (15%)

| Backend | Score | Notes |
|---------|-------|-------|
| Thanos | 9/10 | 4m CPU, 56Mi memory — extremely lean |
| GreptimeDB | 5/10 | 19m CPU, 261Mi — higher baseline footprint |

Thanos is significantly lighter. For a local dev cluster this matters.

### Maturity (10%)

| Backend | Score | Notes |
|---------|-------|-------|
| Thanos | 10/10 | CNCF graduated, v0.37.2, used at massive scale by many organizations |
| GreptimeDB | 6/10 | v0.12.0, growing project, fewer production references. Active development. |

### Storage cost projection (15%)

| Backend | Score | Notes |
|---------|-------|-------|
| Thanos | 8/10 | Uses S3-compatible object storage (versitygw). Well-understood cost model. Compactor reduces storage. |
| GreptimeDB | 7/10 | Also supports S3-compatible storage. Uses columnar format which should compress well. Less proven at scale. |

Both can target versitygw for object storage. Thanos has a more mature compaction
story.

### Weighted total

| Backend | Correctness (20%) | Complexity (40%) | Resources (15%) | Maturity (10%) | Storage (15%) | **Total** |
|---------|-------------------|-----------------|-----------------|---------------|--------------|-----------|
| Thanos | 2.0 | 2.8 | 1.35 | 1.0 | 1.2 | **8.35** |
| GreptimeDB | 2.0 | 3.6 | 0.75 | 0.6 | 1.05 | **8.00** |

---

## Recommendation

**Thanos wins narrowly (8.35 vs 8.00)**, primarily due to its lower resource footprint
and maturity. However, the scores are close enough that the decision should also
consider:

1. **For ystack local dev clusters**: Thanos is preferred — lighter resource usage
   matters in constrained k3d environments, and the 2-component topology (Receive +
   Query) is manageable.

2. **For production multi-cluster**: Thanos is preferred — the Receive component
   already supports multi-tenancy via labels, and the Query component can federate
   across multiple Receive instances. Zone-aware ingestion is well-documented.

3. **GreptimeDB remains interesting** for use cases that need SQL access to metrics
   data or where the standalone deployment model is valued. It could be revisited in
   a future evaluation as the project matures.

## Next steps

1. Remove GreptimeDB from the cluster (losing candidate)
2. Remove dual remote_write — keep only Thanos Receive
3. Add `monitoring/thanos/` to `k3s/30-monitoring/kustomization.yaml`
4. Update validate script to check Thanos components
5. Run `y-cluster-validate-ystack --context=local` to confirm
