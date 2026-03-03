# ystack: Migrate from prometheus-operator to vanilla Prometheus

## Context

ystack provides a monitoring stack that downstream projects inherit. The stack currently
depends on prometheus-operator CRDs. This plan replaces all CRD-based resources with
plain Kubernetes manifests, removing the operator dependency entirely.

The operator manages 5 CRDs in ystack today:

| CRD kind | Name | File | What it does |
|---|---|---|---|
| Prometheus | now | `monitoring/prometheus-now/now-prometheus.yaml` | Deploys Prometheus with 2h retention, auto-discovers ServiceMonitors/PodMonitors |
| Alertmanager | main | `monitoring/alertmanager-main/main-alertmanager.yaml` | Deploys Alertmanager, config from Secret |
| PodMonitor | node-exporter | `monitoring/node-exporter/node-exporter-podmonitor.yaml` | Scrapes node-exporter pods |
| ServiceMonitor | kube-state-metrics | `monitoring/kube-state-metrics/kube-state-metrics-servicemonitor.yaml` | Scrapes kube-state-metrics endpoints |
| PrometheusRule | node-exporter | `monitoring/node-exporter/example-rules.yaml` | Recording rules for CPU metrics |

After migration, no `monitoring.coreos.com` API references will remain. Downstream projects
can then migrate their own PodMonitor/ServiceMonitor/PrometheusRule CRDs to annotations and
config files at their own pace, since the operator itself is no longer installed by ystack.

---

## Target versions

| Component | Current | Target | Notes |
|---|---|---|---|
| Prometheus | operator-managed (v2.x) | v3.10.0 (2026-02-24) | Latest stable, distroless variant |
| Alertmanager | operator-managed | v0.31.0 (2026-02-02) | Latest stable, v2 API only |
| node-exporter | v1.8.1 | v1.8.1 (keep) | No breaking changes needed |
| kube-state-metrics | v2.10.1 | v2.18.0 (2026-01-18) | endpointslices default, new metrics |

### Prometheus v3 migration notes

These affect config and queries:

- **Content-Type strictness**: Add `fallback_scrape_protocol: PrometheusText0.0.4` globally.
  Many workloads lack proper Content-Type headers.
- **`le` label normalization**: `le="1"` becomes `le="1.0"` in histograms. Audit dashboards.
- **Regex `.` matches newlines**: Review relabel regex patterns for `(.+)` or `(.*)`.
  Use `([^\n]+)` if newline matching is undesirable.
- **`expand-external-labels` now default**: Remove feature flag if present.
- **Distroless image UID**: Uses 65532 (nonroot), not 65534 (nobody).
  Update `securityContext.runAsUser` accordingly.
- **Alertmanager v1 API removed**: ystack tests already use v2 API (`/api/v2/alerts`), no change needed.

---

## Step 1: Create Prometheus config files

### 1a. Create `monitoring/prometheus-now/prometheus.yml`

```yaml
global:
  scrape_interval: 30s
  evaluation_interval: 30s
  fallback_scrape_protocol: PrometheusText0.0.4

rule_files:
  - /etc/prometheus/rules/*.yml

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager-main.monitoring.svc.cluster.local:9093

scrape_configs:

  # Scrape Prometheus itself
  - job_name: prometheus
    static_configs:
      - targets: ['localhost:9090']

  # node-exporter: replaces PodMonitor/monitoring/node-exporter
  - job_name: node-exporter
    kubernetes_sd_configs:
      - role: pod
        namespaces:
          names: [monitoring]
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
        action: keep
        regex: node-exporter
      - source_labels: [__meta_kubernetes_pod_node_name]
        target_label: instance

  # kube-state-metrics: replaces ServiceMonitor/monitoring/kube-state-metrics
  - job_name: kube-state-metrics
    kubernetes_sd_configs:
      - role: endpoints
        namespaces:
          names: [monitoring]
    relabel_configs:
      - source_labels: [__meta_kubernetes_service_label_app_kubernetes_io_name]
        action: keep
        regex: kube-state-metrics
      - source_labels: [__meta_kubernetes_endpoint_port_name]
        action: keep
        regex: http-metrics
    honor_labels: true
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: kube_replicaset_status_observed_generation
        action: drop

  # Generic annotation-based pod discovery
  # Pods with prometheus.io/scrape: "true" are scraped automatically.
  # This replaces PodMonitor CRDs for any workload (e.g. kubernetes-assert).
  - job_name: kubernetes-pods
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__
      - source_labels: [__meta_kubernetes_namespace]
        action: replace
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        action: replace
        target_label: pod
      - source_labels: [__meta_kubernetes_pod_node_name]
        action: replace
        target_label: node

  # Generic annotation-based service/endpoint discovery
  # Services with prometheus.io/scrape: "true" are scraped automatically.
  # This replaces ServiceMonitor CRDs for any workload.
  - job_name: kubernetes-service-endpoints
    kubernetes_sd_configs:
      - role: endpoints
    relabel_configs:
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scheme]
        action: replace
        target_label: __scheme__
        regex: (https?)
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_service_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__
      - source_labels: [__meta_kubernetes_namespace]
        action: replace
        target_label: namespace
      - source_labels: [__meta_kubernetes_service_name]
        action: replace
        target_label: service
```

### 1b. Create `monitoring/prometheus-now/rules/node-exporter.yml`

Move the content of the current PrometheusRule CRD into a plain rules file:

```yaml
groups:
  - name: node-exporter-recording-rules
    rules:
      - record: instance:node_cpus:count
        expr: count(node_cpu_seconds_total{mode="idle"}) without (cpu,mode)
      - record: instance_cpu:node_cpu_seconds_not_idle:rate5m
        expr: sum(rate(node_cpu_seconds_total{mode!="idle"}[5m])) without (mode)
      - record: instance_mode:node_cpu_seconds:rate5m
        expr: sum(rate(node_cpu_seconds_total[5m])) without (cpu)
      - record: instance_cpu:node_cpu_top:rate5m
        expr: sum(rate(node_cpu_seconds_total{mode!="idle"}[5m])) without (mode, cpu)
      - record: instance:node_cpu_utilization:ratio
        expr: sum(instance_mode:node_cpu_seconds:rate5m{mode!="idle"}) without (mode) / instance:node_cpus:count
      - record: instance_cpu:node_cpu_top:ratio
        expr: >-
          sum(instance_cpu:node_cpu_top:rate5m) without (mode, cpu)
          /
          sum(rate(node_cpu_seconds_total[5m])) without (mode, cpu)
```

Additional community rules from kubernetes-mixin can be added to this directory later.
The `rule_files` glob (`/etc/prometheus/rules/*.yml`) will pick them up automatically.

---

## Step 2: Replace Prometheus CRD with Deployment

### 2a. Rewrite `monitoring/prometheus-now/now-prometheus.yaml`

Replace the `monitoring.coreos.com/v1 Prometheus` CRD with a plain Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus-now
  labels:
    app.kubernetes.io/name: prometheus
    app.kubernetes.io/instance: now
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: prometheus
      app.kubernetes.io/instance: now
  template:
    metadata:
      labels:
        app.kubernetes.io/name: prometheus
        app.kubernetes.io/instance: now
    spec:
      serviceAccountName: prometheus
      securityContext:
        runAsUser: 65532
        runAsGroup: 65532
        runAsNonRoot: true
        fsGroup: 65532
      containers:
        - name: prometheus
          image: quay.io/prometheus/prometheus:v3.10.0
          args:
            - --config.file=/etc/prometheus/prometheus.yml
            - --storage.tsdb.path=/data
            - --storage.tsdb.retention.time=2h
            - --web.enable-lifecycle
          ports:
            - name: web
              containerPort: 9090
          readinessProbe:
            httpGet:
              path: /-/ready
              port: web
            initialDelaySeconds: 5
          livenessProbe:
            httpGet:
              path: /-/healthy
              port: web
            initialDelaySeconds: 15
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              memory: 512Mi
          volumeMounts:
            - name: config
              mountPath: /etc/prometheus/prometheus.yml
              subPath: prometheus.yml
            - name: rules
              mountPath: /etc/prometheus/rules
            - name: data
              mountPath: /data
        - name: configmap-reload
          image: ghcr.io/jimmidyson/configmap-reload:v0.14.0
          args:
            - --volume-dir=/etc/prometheus
            - --volume-dir=/etc/prometheus/rules
            - --webhook-url=http://127.0.0.1:9090/-/reload
          volumeMounts:
            - name: config
              mountPath: /etc/prometheus/prometheus.yml
              subPath: prometheus.yml
            - name: rules
              mountPath: /etc/prometheus/rules
          resources:
            requests:
              cpu: 5m
              memory: 16Mi
            limits:
              memory: 32Mi
      volumes:
        - name: config
          configMap:
            name: prometheus-now-config
        - name: rules
          configMap:
            name: prometheus-now-rules
        - name: data
          emptyDir: {}
```

### 2b. Update `monitoring/prometheus-now/now-prometheus-service.yaml`

Update selector to match the new Deployment labels:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: prometheus-now
spec:
  ports:
    - name: web
      port: 9090
      protocol: TCP
      targetPort: web
  selector:
    app.kubernetes.io/name: prometheus
    app.kubernetes.io/instance: now
```

### 2c. Update `monitoring/prometheus-now/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: monitoring

resources:
  - ../rbac-prometheus
  - now-prometheus-service.yaml
  - now-prometheus.yaml

configMapGenerator:
  - name: prometheus-now-config
    files:
      - prometheus.yml
  - name: prometheus-now-rules
    files:
      - rules/node-exporter.yml
```

---

## Step 3: Replace Alertmanager CRD with Deployment

### 3a. Rewrite `monitoring/alertmanager-main/main-alertmanager.yaml`

Replace the `monitoring.coreos.com/v1 Alertmanager` CRD with a plain Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alertmanager-main
  labels:
    app.kubernetes.io/name: alertmanager
    app.kubernetes.io/instance: main
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: alertmanager
      app.kubernetes.io/instance: main
  template:
    metadata:
      labels:
        app.kubernetes.io/name: alertmanager
        app.kubernetes.io/instance: main
    spec:
      securityContext:
        runAsUser: 65534
        runAsGroup: 65534
        runAsNonRoot: true
        fsGroup: 65534
      containers:
        - name: alertmanager
          image: quay.io/prometheus/alertmanager:v0.31.0
          args:
            - --config.file=/etc/alertmanager/alertmanager.yaml
            - --storage.path=/data
          ports:
            - name: web
              containerPort: 9093
          readinessProbe:
            httpGet:
              path: /-/ready
              port: web
            initialDelaySeconds: 5
          livenessProbe:
            httpGet:
              path: /-/healthy
              port: web
            initialDelaySeconds: 15
          resources:
            requests:
              cpu: 10m
              memory: 32Mi
            limits:
              memory: 64Mi
          volumeMounts:
            - name: config
              mountPath: /etc/alertmanager
            - name: data
              mountPath: /data
      volumes:
        - name: config
          secret:
            secretName: alertmanager-main
        - name: data
          emptyDir: {}
```

### 3b. Update `monitoring/alertmanager-main/main-alertmanager-service.yaml`

Update selector to match the new Deployment labels:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: alertmanager-main
spec:
  ports:
    - name: web
      port: 9093
      protocol: TCP
      targetPort: web
  selector:
    app.kubernetes.io/name: alertmanager
    app.kubernetes.io/instance: main
```

### 3c. `monitoring/alertmanager-main/kustomization.yaml`

No changes needed. The secretGenerator for `alertmanager-main` from `alertmanager.yaml`
continues to work as-is (with `disableNameSuffixHash: true`).

---

## Step 4: Remove CRD resources from node-exporter and kube-state-metrics

### 4a. `monitoring/node-exporter/kustomization.yaml`

Remove these resources (they no longer exist):
- `node-exporter-podmonitor.yaml`
- `example-rules.yaml`

Result:
```yaml
resources:
  - node-exporter-serviceAccount.yaml
  - node-exporter-clusterRole.yaml
  - node-exporter-clusterRoleBinding.yaml
  - node-exporter-daemonset.yaml
```

### 4b. Delete `monitoring/node-exporter/node-exporter-podmonitor.yaml`

### 4c. Delete `monitoring/node-exporter/example-rules.yaml`

The recording rules now live in `monitoring/prometheus-now/rules/node-exporter.yml`.

### 4d. `monitoring/kube-state-metrics/kustomization.yaml`

Remove `kube-state-metrics-servicemonitor.yaml` resource.

Result:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - cluster-role-binding.yaml
  - cluster-role.yaml
  - deployment.yaml
  - service-account.yaml
  - service.yaml
```

### 4e. Delete `monitoring/kube-state-metrics/kube-state-metrics-servicemonitor.yaml`

---

## Step 5: Simplify -now overlay kustomizations

### 5a. `monitoring/node-exporter-now/kustomization.yaml`

Remove the PodMonitor and PrometheusRule patches (those CRDs no longer exist):

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: monitoring

resources:
  - ../node-exporter
```

### 5b. `monitoring/kube-state-metrics-now/kustomization.yaml`

Remove the ServiceMonitor patch:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: monitoring

resources:
  - ../kube-state-metrics
```

---

## Step 6: Delete prometheus-operator

### 6a. Delete the directory `monitoring/prometheus-operator/`

This removes:
- `monitoring/prometheus-operator/kustomization.yaml` (which pulled the operator from
  `github.com/prometheus-operator/prometheus-operator?ref=6a98ac44054ecddfa857bf6dd2d2f5c7f661992a`)

---

## Step 7: Update provisioning scripts

### 7a. `bin/y-cluster-provision-k3s-lima` (line ~70)

Remove `prometheus-operator \` from the monitoring bases loop:

```bash
[ "$MONITORING_ENABLE" != "true" ] || for base in \
    namespace \
    prometheus-now \
    alertmanager-main \
    kube-state-metrics-now \
    node-exporter-now \
    ; do \
```

### 7b. `bin/y-cluster-provision-k3s-multipass`

Apply the same change if it has a similar monitoring loop.

### 7c. `bin/y-cluster-assert-install`

Remove the prometheus-operator bundle install (lines 17-19):
```bash
# DELETE these lines:
kubectl $ctx -n default create -f https://github.com/prometheus-operator/prometheus-operator/raw/$OPERATOR_VERSION/bundle.yaml
kubectl-waitretry $ctx -n default --for=condition=Ready pod -l app.kubernetes.io/name=prometheus-operator
```

Also remove the `OPERATOR_VERSION` variable (line 5).

---

## Step 8: Update tests

### 8a. `specs/monitoring.spec.js`

The test at line 15 checks for a PodMonitor-style scrape pool:
```js
expect(config.data.yaml).toMatch(/job_name: podMonitor\/monitoring\/kubernetes-assert\/0/);
```

With annotation-based discovery, kubernetes-assert pods need the annotation
`prometheus.io/scrape: "true"`. The scrape pool name becomes `kubernetes-pods`.
Update the test:

```js
expect(config.data.yaml).toMatch(/job_name: kubernetes-pods/);
```

The test at line 21 checks for active targets in that pool. Update:
```js
expect(targets.data.activeTargets).toEqual(
  expect.arrayContaining([
    expect.objectContaining({scrapePool: 'kubernetes-pods'})
  ])
);
```

The Prometheus and Alertmanager API tests (lines 5-13) require no changes.

---

## Modernization notes

### kube-state-metrics v2.18.0

The current deployment uses v2.10.1. Upgrading to v2.18.0 brings:
- endpointslices as default (endpoints discovery deprecated)
- job status metrics, deployment owner tracking, terminating replica counts
- deletion timestamp metrics for multiple resource types

Update the image in `monitoring/kube-state-metrics/deployment.yaml`.

### node-exporter: still necessary

Kubernetes 1.33 added PSI (Pressure Stall Information) metrics to kubelet/cAdvisor, but
node-exporter is still required for per-core CPU modes, detailed memory breakdown,
disk I/O, filesystem fill levels, and load averages. No replacement is available.

### Community recording rules and alerts

The `monitoring/prometheus-now/rules/` directory can be extended with community rules.
The kubernetes-mixin project (https://github.com/kubernetes-monitoring/kubernetes-mixin,
latest version-1.4.2) provides standard recording rules and alerts as jsonnet:

```bash
jb init
jb install github.com/kubernetes-monitoring/kubernetes-mixin@version-1.4.2
jsonnet -J vendor -S -e \
  'std.manifestYamlDoc((import "mixin.libsonnet").prometheusRules)' \
  > monitoring/prometheus-now/rules/kubernetes-mixin-recording.yml
jsonnet -J vendor -S -e \
  'std.manifestYamlDoc((import "mixin.libsonnet").prometheusAlerts)' \
  > monitoring/prometheus-now/rules/kubernetes-mixin-alerts.yml
```

These files are standard Prometheus `rule_files` format and require no operator CRDs.
The rules cover: KubePodCrashLooping, KubeNodeNotReady, KubeCPUOvercommit,
KubeMemoryOvercommit, KubePersistentVolumeFillingUp, CPUThrottlingHigh,
API server availability, and container resource aggregation recording rules.

See also: https://monitoring.mixins.dev/ for the full mixin registry.

---

## Verification checklist

1. `grep -r "monitoring.coreos.com" monitoring/` returns no results
2. `kustomize build monitoring/prometheus-now` produces Deployment + ConfigMaps + Service + RBAC
3. `kustomize build monitoring/alertmanager-main` produces Deployment + Secret + Service
4. `kustomize build monitoring/node-exporter-now` produces DaemonSet + RBAC, no CRDs
5. `kustomize build monitoring/kube-state-metrics-now` produces Deployment + RBAC, no CRDs
6. After applying with `MONITORING_ENABLE=true`, Prometheus is reachable at
   `prometheus-now.monitoring:9090` and reports `reloadConfigSuccess: true`
7. Alertmanager is reachable at `alertmanager-main.monitoring:9093/api/v2/alerts`
8. Prometheus discovers node-exporter and kube-state-metrics targets
9. `specs/monitoring.spec.js` passes
