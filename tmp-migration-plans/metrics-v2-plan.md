# Plan: Replace prometheus-operator with metrics-v2

## Summary

Replace all prometheus-operator CRDs and the operator itself with plain Kubernetes resources in a new `metrics-v2` namespace. This removes the dependency on prometheus-operator while preserving all existing alerting, scraping, and remote-write functionality. The new stack runs alongside the existing `monitoring` namespace during migration.

## Goals

- Remove prometheus-operator as a dependency (CRDs, operator deployment, RBAC)
- Upgrade to Prometheus v3.10.0 and Alertmanager v0.31.1
- Use `metrics-v2` namespace so both stacks coexist during transition
- Require zero changes to `MANUAL_STEPS_FOR_NEW_SITES.md` — new site namespaces are automatically discovered
- Use kustomize `configMapGenerator` hash suffixes as the config reload mechanism (no sidecar reloader)
- Preserve all existing PromQL alert expressions unchanged
- Maintain yaml-language-server schema support for alert rule files

## Non-goals

- Changing any PromQL expressions or alert thresholds
- Migrating the already-ejected `autoscale-v1` Prometheus (it stays as-is in its own namespace)
- Changing Grafana, node-exporter, or kube-state-metrics (they remain in `monitoring`)
- Removing the `monitoring` namespace (done later after validation)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ namespace: metrics-v2                                       │
│                                                             │
│  ┌─────────────────────┐     ┌─────────────────────────┐   │
│  │ DaemonSet:           │     │ StatefulSet:             │   │
│  │ prometheus            │────▶│ alertmanager (2 replicas)│   │
│  │ v3.10.0               │     │ v0.31.1                  │   │
│  │                       │     │ peer mesh on :9094       │   │
│  │ ConfigMap:            │     │                          │   │
│  │  prometheus-config    │     │ ConfigMap:               │   │
│  │  prometheus-rules     │     │  alertmanager-config     │   │
│  └───────────┬───────────┘     └──────────────────────────┘   │
│              │                                               │
│              │ remote_write                                   │
│              ▼                                               │
│  mimir-distributor.mimir.svc:8080/api/v1/push               │
└─────────────────────────────────────────────────────────────┘
```

Each Prometheus DaemonSet pod scrapes only pods on its own node using `__meta_kubernetes_pod_node_name` filtering, reducing cross-node traffic. All data goes to Mimir via remote_write, which deduplicates based on `__replica__` external label.

Service discovery uses `kubernetes_sd_configs` with `role: pod` and `role: endpoints` **without namespace restrictions**, so pods in any namespace (including future site namespaces) are automatically discovered based on `prometheus.io/scrape: "true"` annotations.

## Prometheus v3 migration notes

Reference: https://prometheus.io/docs/prometheus/latest/migration/

Key changes that affect this migration:

| Change | Impact |
|--------|--------|
| `expand-external-labels` is now default | `${NODE_NAME}` in `external_labels` works natively — no init container needed |
| `fallback_scrape_protocol` required | Many workloads lack Content-Type headers; set `fallback_scrape_protocol: PrometheusText0.0.4` globally |
| Alertmanager API v1 removed | v0.31.1 uses v2 only; no `api_version` config needed |
| `le` label normalization | `le="1"` becomes `le="1.0"` in classic histograms. Audit dashboards/alerts referencing `le` labels |
| Remote write `enable_http2` defaults to `false` | Fine for Mimir; no action needed |
| Range selectors now left-open | Subqueries like `foo[1m:1m]` may return fewer samples. Audit recording rules |
| `.` in regex now matches newlines | Review relabel regex patterns for unintended matches |

## Implementation steps

### Step 1: Create directory structure

Create `metrics-v2/` at the repo root with this layout:

```
metrics-v2/
├── kustomization.yaml
├── namespace.yaml
├── prometheus-daemonset.yaml
├── prometheus-rbac.yaml
├── prometheus.yaml              # prometheus config (→ configMapGenerator)
├── alertmanager-statefulset.yaml
├── alertmanager.yaml            # alertmanager config (→ configMapGenerator)
└── rules/
    ├── gateway-alerts.yaml
    ├── keda-alerts.yaml
    ├── redpanda-alerts.yaml
    ├── keycloak-v3-alerts.yaml
    ├── rest-v1-alerts.yaml
    ├── outside-v1-alerts.yaml
    ├── certificate-alerts.yaml
    └── k8s-mixin-alerts.yaml
```

### Step 2: Create the namespace

```yaml
# metrics-v2/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: metrics-v2
```

### Step 3: Create RBAC

Prometheus needs cluster-wide read access for cross-namespace pod/endpoint discovery.

```yaml
# metrics-v2/prometheus-rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
  namespace: metrics-v2
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: metrics-v2-prometheus
rules:
- apiGroups: [""]
  resources: [nodes, nodes/metrics, services, endpoints, pods]
  verbs: [get, list, watch]
- apiGroups: ["networking.k8s.io"]
  resources: [ingresses]
  verbs: [get, list, watch]
- nonResourceURLs: [/metrics]
  verbs: [get]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: metrics-v2-prometheus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: metrics-v2-prometheus
subjects:
- kind: ServiceAccount
  name: prometheus
  namespace: metrics-v2
```

### Step 4: Create Prometheus DaemonSet

```yaml
# metrics-v2/prometheus-daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: prometheus
  namespace: metrics-v2
  labels:
    app: prometheus
spec:
  selector:
    matchLabels:
      app: prometheus
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      serviceAccountName: prometheus
      securityContext:
        runAsUser: 65534
        runAsGroup: 65534
        fsGroup: 65534
      priorityClassName: yolean-alerting
      terminationGracePeriodSeconds: 300
      containers:
      - name: prometheus
        image: quay.io/prometheus/prometheus:v3.10.0
        args:
        - --config.file=/etc/prometheus/prometheus.yaml
        - --storage.tsdb.retention.time=90m
        - --storage.tsdb.path=/prometheus
        - --web.enable-lifecycle
        - --web.route-prefix=/
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        ports:
        - name: web
          containerPort: 9090
          protocol: TCP
        readinessProbe:
          httpGet:
            path: /-/ready
            port: web
          periodSeconds: 5
          timeoutSeconds: 3
        startupProbe:
          httpGet:
            path: /-/ready
            port: web
          failureThreshold: 60
          periodSeconds: 1
          timeoutSeconds: 3
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: [ALL]
          readOnlyRootFilesystem: true
        resources:
          requests:
            cpu: 1
            memory: 11500Mi
        volumeMounts:
        - name: config
          mountPath: /etc/prometheus
          readOnly: true
        - name: rules
          mountPath: /etc/prometheus/rules
          readOnly: true
        - name: data
          mountPath: /prometheus
      volumes:
      - name: config
        configMap:
          name: prometheus-config
      - name: rules
        configMap:
          name: prometheus-rules
      - name: data
        emptyDir:
          sizeLimit: 4Gi
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: metrics-v2
spec:
  clusterIP: None
  ports:
  - name: web
    port: 9090
    targetPort: web
  selector:
    app: prometheus
```

Note: `emptyDir` for TSDB is acceptable because retention is only 90m and all data is remote-written to Mimir. The current setup also uses minimal local storage.

### Step 5: Create Prometheus config

This is the core of the migration. The config uses annotation-based discovery with no namespace restrictions, ensuring new site namespaces are automatically scraped.

Prometheus v3 expands `${NODE_NAME}` in external_labels natively (the `expand-external-labels` feature flag is now default behavior), so each DaemonSet pod identifies itself by node name.

```yaml
# metrics-v2/prometheus.yaml
global:
  evaluation_interval: 30s
  scrape_interval: 15s
  external_labels:
    cluster: g2
    region: europe-west4
    __replica__: ${NODE_NAME}
  # Prometheus v3: most workloads lack Content-Type headers
  fallback_scrape_protocol: PrometheusText0.0.4

rule_files:
- /etc/prometheus/rules/*.yaml

remote_write:
- name: mimir
  url: http://mimir-distributor.mimir.svc.cluster.local:8080/api/v1/push
  queue_config:
    capacity: 10
    retry_on_http_429: false
  write_relabel_configs:
  - source_labels: [__name__]
    regex: "ALERTS|live_.+|forecast_worker_.+|broker_.+|workerpods_.+|boards_.+|kkv_.+|notifications_.*|sendgrid_.+|support_requests_.*|restv1_.+|kminion_kafka_topic_high_water_mark_sum|envoy_cluster_upstream_rq|envoy_cluster_upstream_rq_timeout|envoy_cluster_upstream_cx_connect_timeout|keda_.+|container_network_transmit_bytes_total|container_network_receive_bytes_total|redpanda_cluster_partition_moving_*|redpanda_node_status_rpcs_timed_out|redpanda_rpc_request_errors_total|redpanda_cpu_busy_seconds_total|machine_cpu_cores|machine_memory_bytes|issuereports_issues_reported_total|keycloak_user_events_total|envoy_http_oauth_failure|envoy_http_csrf_request_invalid|kube_pod_status_scheduled_time|kube_pod_status_initialized_time|kube_pod_status_ready_time|kube_pod_container_state_started|nodejs_eventloop_lag_.*"
    action: keep

alerting:
  alertmanagers:
  - static_configs:
    - targets: ['alertmanager.metrics-v2.svc.cluster.local:9093']

scrape_configs:

# ---------------------------------------------------------------------------
# Generic annotation-based pod discovery — ALL namespaces
# Replaces: all PodMonitors that don't need custom metric_relabel_configs
# New sites are automatically discovered — no config change needed
# ---------------------------------------------------------------------------
- job_name: kubernetes-pods
  kubernetes_sd_configs:
  - role: pod
  relabel_configs:
  # Only scrape pods with annotation
  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
    action: keep
    regex: "true"
  # DaemonSet: each instance only scrapes pods on its own node
  - source_labels: [__meta_kubernetes_pod_node_name]
    action: keep
    regex: ${NODE_NAME}
  # Drop terminated pods
  - source_labels: [__meta_kubernetes_pod_phase]
    action: drop
    regex: (Failed|Succeeded)
  # Custom path from annotation
  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
    action: replace
    target_label: __metrics_path__
    regex: (.+)
  # Custom port from annotation
  - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
    action: replace
    regex: ([^:]+)(?::\d+)?;(\d+)
    replacement: $1:$2
    target_label: __address__
  # Standard labels
  - source_labels: [__meta_kubernetes_namespace]
    target_label: namespace
  - source_labels: [__meta_kubernetes_pod_name]
    target_label: pod
  - source_labels: [__meta_kubernetes_pod_container_name]
    target_label: container
  - source_labels: [__meta_kubernetes_pod_label_app]
    target_label: job
    regex: (.+)
  - source_labels: [__meta_kubernetes_pod_label_site]
    target_label: site
    regex: (.+)

# ---------------------------------------------------------------------------
# Generic annotation-based endpoint/service discovery — ALL namespaces
# Replaces: all ServiceMonitors
# ---------------------------------------------------------------------------
- job_name: kubernetes-endpoints
  kubernetes_sd_configs:
  - role: endpoints
  relabel_configs:
  - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scrape]
    action: keep
    regex: "true"
  - source_labels: [__meta_kubernetes_pod_node_name]
    action: keep
    regex: ${NODE_NAME}
  - source_labels: [__meta_kubernetes_pod_phase]
    action: drop
    regex: (Failed|Succeeded)
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
    target_label: namespace
  - source_labels: [__meta_kubernetes_service_name]
    target_label: service
  - source_labels: [__meta_kubernetes_pod_name]
    target_label: pod
  - source_labels: [__meta_kubernetes_pod_label_app]
    target_label: job
    regex: (.+)
  - source_labels: [__meta_kubernetes_pod_label_site]
    target_label: site
    regex: (.+)

# ---------------------------------------------------------------------------
# Infrastructure-specific jobs
# These target fixed cluster-level namespaces with custom metrics_path
# or metric_relabel_configs. NOT per-site — no MANUAL_STEPS impact.
# ---------------------------------------------------------------------------

- job_name: redpanda
  kubernetes_sd_configs:
  - role: pod
    namespaces:
      names: [kafka-v3]
  metrics_path: /public_metrics
  relabel_configs:
  - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
    action: keep
    regex: redpanda
  - source_labels: [__meta_kubernetes_pod_container_port_name]
    action: keep
    regex: admin
  - source_labels: [__meta_kubernetes_pod_node_name]
    action: keep
    regex: ${NODE_NAME}
  - source_labels: [__meta_kubernetes_pod_phase]
    action: drop
    regex: (Failed|Succeeded)
  - source_labels: [__meta_kubernetes_namespace]
    target_label: namespace
  - source_labels: [__meta_kubernetes_pod_name]
    target_label: pod
  metric_relabel_configs:
  - regex: redpanda_namespace
    action: labeldrop

- job_name: keycloak
  kubernetes_sd_configs:
  - role: pod
    namespaces:
      names: [keycloak-v3]
  metrics_path: /auth/metrics
  relabel_configs:
  - source_labels: [__meta_kubernetes_pod_label_app]
    action: keep
    regex: keycloak
  - source_labels: [__meta_kubernetes_pod_container_port_name]
    action: keep
    regex: management
  - source_labels: [__meta_kubernetes_pod_node_name]
    action: keep
    regex: ${NODE_NAME}
  - source_labels: [__meta_kubernetes_pod_phase]
    action: drop
    regex: (Failed|Succeeded)
  - source_labels: [__meta_kubernetes_namespace]
    target_label: namespace
  - source_labels: [__meta_kubernetes_pod_name]
    target_label: pod
  metric_relabel_configs:
  - source_labels: [__name__]
    regex: (vendor_jgroups_tcp.*|vendor_jgroups_merge3.*|worker_pool_ratio|http_server_.*|keycloak_user_events_total)
    action: keep

- job_name: kafka-jmx
  kubernetes_sd_configs:
  - role: endpoints
    namespaces:
      names: [kafka]
  scrape_interval: 120s
  scrape_timeout: 119s
  relabel_configs:
  - source_labels: [__meta_kubernetes_service_label_app]
    action: keep
    regex: kafka
  - source_labels: [__meta_kubernetes_endpoint_port_name]
    action: keep
    regex: fromjmx
  - source_labels: [__meta_kubernetes_pod_node_name]
    action: keep
    regex: ${NODE_NAME}
  - source_labels: [__meta_kubernetes_pod_phase]
    action: drop
    regex: (Failed|Succeeded)
  - source_labels: [__meta_kubernetes_namespace]
    target_label: namespace
  - source_labels: [__meta_kubernetes_pod_name]
    target_label: pod
  - source_labels: [__meta_kubernetes_service_name]
    target_label: service
```

### Step 6: Create Alertmanager StatefulSet

```yaml
# metrics-v2/alertmanager-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: alertmanager
  namespace: metrics-v2
  labels:
    app: alertmanager
spec:
  serviceName: alertmanager
  replicas: 2
  podManagementPolicy: Parallel
  selector:
    matchLabels:
      app: alertmanager
  template:
    metadata:
      labels:
        app: alertmanager
    spec:
      securityContext:
        runAsUser: 65534
        runAsGroup: 65534
        fsGroup: 65534
      terminationGracePeriodSeconds: 120
      containers:
      - name: alertmanager
        image: quay.io/prometheus/alertmanager:v0.31.1
        args:
        - --config.file=/etc/alertmanager/alertmanager.yaml
        - --storage.path=/alertmanager
        - --cluster.listen-address=[$(POD_IP)]:9094
        - --cluster.peer=alertmanager-0.alertmanager.metrics-v2.svc.cluster.local:9094
        - --cluster.peer=alertmanager-1.alertmanager.metrics-v2.svc.cluster.local:9094
        env:
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        ports:
        - name: web
          containerPort: 9093
        - name: mesh
          containerPort: 9094
        readinessProbe:
          httpGet:
            path: /-/ready
            port: web
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /-/healthy
            port: web
          periodSeconds: 30
        resources:
          requests:
            cpu: 10m
            memory: 64Mi
          limits:
            memory: 128Mi
        volumeMounts:
        - name: config
          mountPath: /etc/alertmanager
          readOnly: true
        - name: data
          mountPath: /alertmanager
      volumes:
      - name: config
        configMap:
          name: alertmanager-config
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ReadWriteOnce]
      resources:
        requests:
          storage: 1Gi
---
apiVersion: v1
kind: Service
metadata:
  name: alertmanager
  namespace: metrics-v2
spec:
  clusterIP: None
  ports:
  - name: web
    port: 9093
    targetPort: web
  - name: mesh
    port: 9094
    targetPort: mesh
  selector:
    app: alertmanager
```

### Step 7: Copy Alertmanager config

Copy `monitoring/cluster-backend/alertmanager.yaml` as-is — it is already valid Alertmanager config.

```yaml
# metrics-v2/alertmanager.yaml
# Copied from monitoring/cluster-backend/alertmanager.yaml — no changes needed
global:
  resolve_timeout: 5m
route:
  receiver: 'null'
  routes:
  - receiver: internal
    repeat_interval: 10m
    continue: true
  - match:
      alertname: DeadMansSwitch
  - match:
      severity: none
  - match:
      namespace: qa
    routes:
    - match:
        alertname: KubePersistentVolumeFillingUp
      routes:
      - receiver: opsgenie
        continue: true
      - receiver: ilert
        continue: true
  - match:
      site: qa
  - match:
      namespace: dev2
  - match:
      site: dev2
  - match:
      namespace: dev3
  - match:
      site: dev3
  - match:
      namespace: dev5
  - match:
      site: dev5
  - match:
      alertname: YLiveQueryLatencyHigh
      namespace: yolean
  - match:
      alertname: YBoardsProxyHTTPStatus5XXIncreasing
  - match:
      alertname: YBoardsProxyHTTPStatus4XXIncreasing
  - match:
      alertname: EnvoyStatus
  - match:
      severity: warning
  - receiver: opsgenie
    group_by: ['...']
    repeat_interval: 1h
    continue: true
  - receiver: ilert
    routes:
    - match:
        job: kube-state-metrics
      group_by:
      - cluster
      - namespace
      - alertname
    - group_by: ['...']
    continue: true
receivers:
- name: opsgenie
  opsgenie_configs:
  - api_key: 5ef6aa66-0f2b-4c9b-b419-b43ff06c1728
    api_url: https://api.eu.opsgenie.com/
- name: ilert
  webhook_configs:
  - url: 'https://api.ilert.com/api/v1/events/prometheus/il1prom0721f34364b1479740cfbea29b7391d93f0bcb3c689569'
- name: internal
  webhook_configs:
  - url: 'http://alerts-hook.svc.yolean.se:8080/hook/v1/alertmanager'
- name: 'null'
```

### Step 8: Extract alert rules from PrometheusRule CRDs

Each PrometheusRule CRD's `spec.groups` becomes a plain Prometheus rule file. The PromQL expressions are unchanged. Add yaml-language-server schema annotation for editor support.

The following files must be created in `metrics-v2/rules/`. For each, the transformation is:
- Remove the `apiVersion`, `kind`, `metadata`, `spec` wrapper
- Keep only the `groups:` array
- Add `# yaml-language-server: $schema=https://json.schemastore.org/prometheus.rules.json` at the top

Source files and their targets:

| Source (PrometheusRule CRD) | Target (plain rule file) |
|---|---|
| `gateway-v4/cluster-backend-monitoring/gateway-alerts.yaml` | `metrics-v2/rules/gateway-alerts.yaml` |
| `autoscale-v1/keda-monitoring/keda-alerts.yaml` | `metrics-v2/rules/keda-alerts.yaml` |
| `kafka-v3/cluster-backend-monitoring/redpanda-alerts.yaml` | `metrics-v2/rules/redpanda-alerts.yaml` |
| `keycloak-v3/cluster-backend-monitoring/keycloak-v3-alerts.yaml` | `metrics-v2/rules/keycloak-v3-alerts.yaml` |
| `rest-v1/cluster-backend-monitoring/rest-v1-alerts.yaml` | `metrics-v2/rules/rest-v1-alerts.yaml` |
| `outside-v1/alerts/gcs-stats-alerts.yaml` | `metrics-v2/rules/outside-v1-alerts.yaml` (merge both outside-v1 files) |
| `outside-v1/alerts/mails-blocked-increasing.yaml` | (merged into `outside-v1-alerts.yaml`) |
| `cluster-g2/cert-manager/alerts/certificate-alerts.yaml` | `metrics-v2/rules/certificate-alerts.yaml` |
| `monitoring/k8s-alerts/k8s-alerts.yaml` + `monitoring/cluster-backend/kubernetes-mixin-alerts-overrides.yaml` | `metrics-v2/rules/k8s-mixin-alerts.yaml` |

Example transformation:

```yaml
# metrics-v2/rules/gateway-alerts.yaml
# yaml-language-server: $schema=https://json.schemastore.org/prometheus.rules.json
groups:
- name: gateway
  rules:
  - alert: YGatewayConnectTimeout
    annotations:
      message: Timeout {{ $labels.yolean_se_site }} {{ $labels.envoy_cluster_name }}
    expr: >-
      rate(envoy_cluster_upstream_cx_connect_timeout{job!="ops-gateway",envoy_cluster_name!="poll-to-reload"}[1m]) > 0
    labels:
      severity: critical
  # ... remaining rules copied verbatim from the CRD's spec.groups[0].rules
```

The recording rules from `monitoring/k8s-alerts/k8s-alerts.yaml` (node-exporter section) must also be included:

```yaml
# metrics-v2/rules/k8s-mixin-alerts.yaml
# yaml-language-server: $schema=https://json.schemastore.org/prometheus.rules.json
groups:
- name: kubernetes-storage
  rules:
  - alert: KubePersistentVolumeErrors
    annotations:
      description: The persistent volume {{ $labels.persistentvolume }} has status {{ $labels.phase }}.
      summary: PersistentVolume is having issues with provisioning.
    expr: |
      kube_persistentvolume_status_phase{phase=~"Failed|Pending",job="kube-state-metrics"} > 0
    for: 5m
    labels:
      severity: critical
- name: kubernetes-resources
  rules:
  - alert: CPUThrottlingHigh
    labels:
      severity: warning
- name: example-node-exporter-rules
  rules:
  - expr: |
      sum by (cluster, namespace, pod, container) (
        irate(container_cpu_usage_seconds_total{job="kubelet", metrics_path="/metrics/cadvisor", image!=""}[5m])
      ) * on (cluster, namespace, pod) group_left(node) topk by (cluster, namespace, pod) (
        1, max by(cluster, namespace, pod, node) (kube_pod_info{node!=""})
      )
    record: node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate
  - expr: sum(instance_mode:node_cpu_seconds:rate5m{mode!="idle"}) without (mode) / instance:node_cpus:count
    record: instance:node_cpu_utilization:ratio
```

### Step 9: Create kustomization.yaml

```yaml
# metrics-v2/kustomization.yaml
# yaml-language-server: $schema=https://json.schemastore.org/kustomization.json
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: metrics-v2

resources:
- namespace.yaml
- prometheus-daemonset.yaml
- prometheus-rbac.yaml
- alertmanager-statefulset.yaml

configMapGenerator:
- name: prometheus-config
  files:
  - prometheus.yaml
- name: prometheus-rules
  files:
  - rules/gateway-alerts.yaml
  - rules/keda-alerts.yaml
  - rules/redpanda-alerts.yaml
  - rules/keycloak-v3-alerts.yaml
  - rules/rest-v1-alerts.yaml
  - rules/outside-v1-alerts.yaml
  - rules/certificate-alerts.yaml
  - rules/k8s-mixin-alerts.yaml
- name: alertmanager-config
  files:
  - alertmanager.yaml
```

### Step 10: Add pod annotations to workloads

Each workload currently scraped via PodMonitor or ServiceMonitor must add `prometheus.io/*` annotations to its pod template. This is the workload-side migration that allows the generic `kubernetes-pods` scrape job to discover them.

#### Site-chart Helm templates (replaces PodMonitor templates)

The three PodMonitor templates in `kube/site-chart/templates/` are deleted. Instead, the Helm chart adds annotations to pod templates of workloads that previously had matching labels:

| Deleted template | Previously matched via label | Annotations to add to pod template |
|---|---|---|
| `singlequarkus-podmonitor.yaml` | `scrape: singlequarkus` | `prometheus.io/scrape: "true"`, `prometheus.io/port: "<http port number>"`, `prometheus.io/path: "/q/metrics"` |
| `slashmetricshttp-podmonitor.yaml` | `scrape: slashmetricshttp` | `prometheus.io/scrape: "true"`, `prometheus.io/port: "<http port number>"`, `prometheus.io/path: "/metrics"` |
| `singleenvoy-podmonitor.yaml` | `scrape: singleenvoy` | `prometheus.io/scrape: "true"`, `prometheus.io/port: "<admin port number>"`, `prometheus.io/path: "/stats/prometheus"` |

The `scrape: *` labels on pods can remain (they're still useful as descriptive labels) but are no longer used for discovery.

#### Infrastructure PodMonitors (replaced by explicit scrape jobs or annotations)

These PodMonitors are deleted because their targets are either handled by the generic `kubernetes-pods` job (if they add annotations) or by the explicit infrastructure scrape jobs in the prometheus config:

| Deleted PodMonitor | Replacement |
|---|---|
| `kafka-v3/cluster-backend/redpanda-podmonitor.yaml` | Explicit `redpanda` scrape job in prometheus.yaml |
| `keycloak-v3/cluster-backend/keycloak-podmonitor.yaml` | Explicit `keycloak` scrape job in prometheus.yaml |
| `keycloak-v3/cluster-backend-emails/keycloak-emails-podmonitor.yaml` | Add annotations to keycloak-emails pod |
| `gateway-v4/site-apply/authz-podmonitor.yaml` | Add annotations to gateway-v4-authz pod |
| `gateway-v3/cluster-backend/gateway-v3-podmonitor.yaml` | Add annotations to gateway pod |
| `gateway-v3/fallback-pages/fallback-pages-podmonitor.yaml` | Add annotations to fallback-pages pod |
| `gateway-v3/cluster-ops/ops-gateway-podmonitor.yaml` | Add annotations to ops-gateway pod |
| `autoscale-v1/keda/keda-operator-podmonitor.yaml` | Add annotations to keda-operator pod |
| `prints-v2/site-apply/prints-v2-podmonitor.yaml` | Add annotations to prints-v2 worker pod |
| `events-v1/site-apply/events-v1-podmonitor.yaml` | Add annotations to events-v1-backend pod |
| `stats-v2/cluster-backend/stats-v2-workflows-podmonitor.yaml` | Add annotations to workflows pod |
| `cicd-v1/cluster-backend/pipelines-podmonitor.yaml` | Add annotations to tekton-pipelines pods |
| `upgrades-v1/cluster-backend/cicd-v1-job-podmonitor.yaml` | Add annotations to cicd-v1 sitesetup pod |
| `cluster-g2/logs/loki-podmonitor.yaml` | Add annotations to loki pod |
| `outside-v1/cluster-backend/outside-v1-eventrouter-podmonitor.yaml` | Add annotations to eventrouter pod |
| `orgsetup-v2/cluster-backend-webhook/yoleanorg-conversion-webhook-podmonitor.yaml` | Add annotations to conversion webhook pod |
| `analytics-v3/cluster-backend/podmonitor.yaml` | Add annotations to mariadb pod |

#### ServiceMonitors (replaced by annotations)

| Deleted ServiceMonitor | Replacement |
|---|---|
| `monitoring/kafka-servicemonitor.yaml` | Explicit `kafka-jmx` scrape job (needs bearer token, custom interval) |
| `logs/server/k8s/servicemonitor.yaml` | Add `prometheus.io/scrape: "true"` annotation to logs-server service |
| `kafka-v2/cluster-backend/kminion-servicemonitor.yaml` | Add `prometheus.io/scrape: "true"` annotation to kminion service |
| `kube/cautionary-bot/k8s/servicemonitor.yaml` | Add `prometheus.io/scrape: "true"` annotation to cautionary-bot service |

#### Annotation format

For each workload, add these annotations to the **pod template spec** (not the Service or Deployment metadata):

```yaml
spec:
  template:
    metadata:
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"          # the metrics port number
        prometheus.io/path: "/metrics"       # if non-default
```

For services using the `kubernetes-endpoints` job, add annotations to the **Service metadata**:

```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
```

### Step 11: Metric filtering migration

Several current PodMonitors drop or keep specific metrics via `metricRelabelings`. With the annotation-based generic job, per-workload metric filtering is not directly possible (without adding more annotation conventions). The recommended approach for each case:

| PodMonitor | Current filtering | Recommendation |
|---|---|---|
| singlequarkus | Drops `jvm_*`, `netty_*` | Accept scraping these; they're dropped by remote_write's metric regex anyway (not in the keep list) |
| slashmetricshttp | Drops `go_*`, `tokio_*`, `nodejs_active_*`, `nodejs_heap_*`, `nodejs_external_*`, `nodejs_gc_*` | Same — dropped by remote_write filter |
| singleenvoy | Keeps only `envoy_cluster_upstream_rq_total`, `envoy_http_downstream_cx_active` | Same — only metrics matching the remote_write regex reach Mimir |
| gateway-v4-authz | Drops specific `envoy_cluster_membership_*` for certain cluster names | Minor overhead; these don't match the remote_write keep regex |
| redpanda (now) | Drops `redpanda_namespace` label | Handled by explicit `redpanda` scrape job with `metric_relabel_configs` |
| keycloak | Keeps only specific metrics | Handled by explicit `keycloak` scrape job with `metric_relabel_configs` |

The local TSDB (90m retention, emptyDir) absorbs the slightly higher cardinality. Only metrics matching the remote_write regex are sent to Mimir, so there's no impact on long-term storage costs.

### Step 12: Cluster-specific kustomize overlay (for cluster-sites0)

Create a variant for clusters with different external labels or Mimir endpoints:

```yaml
# cluster-sites0/metrics-v2/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- ../../metrics-v2

patches:
- target:
    kind: ConfigMap
    name: prometheus-config
  # Override external_labels and remote_write URL for this cluster
```

Or maintain separate `prometheus.yaml` per cluster and use `configMapGenerator` with `behavior: replace`.

### Step 13: Validate and deploy

1. Build and dry-run: `kustomize build metrics-v2/ | kubectl --context=g2 diff -f -`
2. Apply namespace + RBAC first: `kubectl --context=g2 apply -f metrics-v2/namespace.yaml -f metrics-v2/prometheus-rbac.yaml`
3. Apply full stack: `kustomize build metrics-v2/ | kubectl --context=g2 apply -f -`
4. Verify Prometheus targets: port-forward to prometheus:9090 and check `/targets`
5. Verify alerts firing: check `/alerts` on Prometheus UI
6. Compare with existing stack: both should show the same active alerts
7. During validation period, the `metrics-v2` alertmanager should route to `internal` only (not opsgenie/ilert) to avoid duplicate pages

### Step 14: Cutover (after validation)

1. Update `metrics-v2/alertmanager.yaml` to include opsgenie and ilert receivers
2. Disable alerting in the old `monitoring` Prometheus (remove routes or scale to 0)
3. Remove prometheus-operator from `cluster-g2/default/kustomization.yaml` (the `github.com/solsson/prometheus-operator/example/` resource)
4. Remove all PodMonitor, ServiceMonitor, PrometheusRule YAML files listed in Step 10
5. Remove the Prometheus and Alertmanager CRD resources from `monitoring/` kustomizations
6. Optionally remove the CRDs themselves (after confirming nothing else uses them)

## Files to delete after cutover

All PodMonitor files (18 files):
- `gateway-v4/site-apply/authz-podmonitor.yaml`
- `gateway-v3/cluster-backend/gateway-v3-podmonitor.yaml`
- `gateway-v3/fallback-pages/fallback-pages-podmonitor.yaml`
- `gateway-v3/cluster-ops/ops-gateway-podmonitor.yaml`
- `kafka-v3/cluster-backend/redpanda-podmonitor.yaml`
- `keycloak-v3/cluster-backend/keycloak-podmonitor.yaml`
- `keycloak-v3/cluster-backend-emails/keycloak-emails-podmonitor.yaml`
- `autoscale-v1/keda/keda-operator-podmonitor.yaml`
- `prints-v2/site-apply/prints-v2-podmonitor.yaml`
- `events-v1/site-apply/events-v1-podmonitor.yaml`
- `stats-v2/cluster-backend/stats-v2-workflows-podmonitor.yaml`
- `cicd-v1/cluster-backend/pipelines-podmonitor.yaml`
- `upgrades-v1/cluster-backend/cicd-v1-job-podmonitor.yaml`
- `cluster-g2/logs/loki-podmonitor.yaml`
- `outside-v1/cluster-backend/outside-v1-eventrouter-podmonitor.yaml`
- `orgsetup-v2/cluster-backend-webhook/yoleanorg-conversion-webhook-podmonitor.yaml`
- `analytics-v3/cluster-backend/podmonitor.yaml`
- `kube/site-chart/templates/singlequarkus-podmonitor.yaml`
- `kube/site-chart/templates/slashmetricshttp-podmonitor.yaml`
- `kube/site-chart/templates/singleenvoy-podmonitor.yaml`

All ServiceMonitor files (5 files):
- `monitoring/kafka-servicemonitor.yaml`
- `logs/server/k8s/servicemonitor.yaml`
- `kafka-v2/cluster-backend/kminion-servicemonitor.yaml`
- `kube/cautionary-bot/k8s/servicemonitor.yaml`
- `autoscale-v1/prometheus/redpanda-servicemonitor.yaml`

All PrometheusRule files (10 files):
- `gateway-v4/cluster-backend-monitoring/gateway-alerts.yaml`
- `autoscale-v1/keda-monitoring/keda-alerts.yaml`
- `kafka-v3/cluster-backend-monitoring/redpanda-alerts.yaml`
- `keycloak-v3/cluster-backend-monitoring/keycloak-v3-alerts.yaml`
- `rest-v1/cluster-backend-monitoring/rest-v1-alerts.yaml`
- `outside-v1/alerts/gcs-stats-alerts.yaml`
- `outside-v1/alerts/mails-blocked-increasing.yaml`
- `cluster-g2/cert-manager/alerts/certificate-alerts.yaml`
- `monitoring/k8s-alerts/k8s-alerts.yaml`
- `monitoring/cluster-backend/kubernetes-mixin-alerts-overrides.yaml`

Prometheus-operator references (3 files to edit):
- `cluster-g2/default/kustomization.yaml` — remove `github.com/solsson/prometheus-operator/example/` resource and patches
- `cluster-sites0/default/kustomization.yaml` — same
- `cluster-local/default/kustomization.yaml` — same

Prometheus CRD patch files in `cluster-g2/monitoring/` (5 files):
- `now-prometheus-scale.yaml`
- `now-prometheus-resources.yaml`
- `now-prometheus-labels.yaml`
- `now-prometheus-preemptible.yaml`
- `now-prometheus-write-mimir.yaml`

Alertmanager CRD patch files:
- `cluster-g2/monitoring/main-alertmanager-scale-2.yaml`

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Duplicate alerts during coexistence period | Route metrics-v2 alertmanager to `internal` webhook only during validation |
| Missing scrape targets | Compare `/targets` page between old and new Prometheus before cutover |
| Prometheus v3 PromQL changes break alerts | All alert expressions are unchanged; `le` normalization is the main concern — audit dashboards |
| DaemonSet resource overhead (one Prometheus per node) | Memory/CPU requests can be tuned down per node since each instance scrapes fewer targets |
| Config change requires pod restart (no live reload) | Acceptable given kustomize hash-based rolling updates; `--web.enable-lifecycle` is available as fallback for manual `/-/reload` calls |
| `${NODE_NAME}` expansion in scrape_configs relabel rules | Prometheus v3 expands env vars in config natively via `expand-external-labels` default. Verify that relabel `regex: ${NODE_NAME}` works or use `__meta_kubernetes_pod_node_name` matching against external label instead |

## Open questions for review

1. **DaemonSet vs Deployment**: A DaemonSet means one Prometheus per node. The current setup uses `replicas: 1`. A single-replica Deployment would be simpler but less resilient. The DaemonSet approach gives per-node scraping (less cross-node traffic) and survives node failures, but uses more total resources. Which is preferred?

2. **Resource sizing for DaemonSet pods**: The current Prometheus requests 1 CPU + 11.5Gi memory for a single instance scraping the entire cluster. With a DaemonSet, each pod only scrapes its local node's pods, so requests should be significantly lower. What's the right per-node sizing?

3. **Metric filtering at scrape time vs write time**: The current PodMonitors filter metrics at scrape time (e.g. drop `jvm_*`). The proposed design scrapes all metrics and relies on `write_relabel_configs` to filter what goes to Mimir. This increases local TSDB cardinality but simplifies config. Is this acceptable?

4. **cluster-sites0 strategy**: Should cluster-sites0 get its own overlay immediately, or is this a g2-first migration?

5. **alerts-hook-federation service**: The `alerts-hook-federation.yaml` in `cluster-g2/monitoring/` provides external DNS for `alerts-hook.svc.yolean.se`. This likely needs to remain in `monitoring` or be duplicated. Confirm the right approach.
