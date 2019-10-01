# Monitoring stack

We've observed... that when developers start to factor in
the existence of metrics collection ("scrape") and alerting rules
-- both generic such as not-enough-replicas or job-failed and service specific --
it becomes a handy solution to many difficult coding problems.
Instead of error handling by assumption we expose a metric on some case
and make sure the alert for it works.
Helps immensely to leave it to humans to interpret the condition,
instead of implementing an automated solution up front.

At Yolean we've run [kube-prometheus](https://github.com/coreos/kube-prometheus) for many years
but, while it is a good collection of tools + rules + dashboards,
we feel it is time to start to opt-in to components individuallly.

Requirements:
 * Lean enough to be always-on in development clusters.
 * Expose alerts that a dev environment can poll for,
   to make monitoring + alerting rules a first class impl tool.
 * Comes with basic sanity checks on the stack.

Tools:
 * Prometheus, the de-facto standard with k8s
 * Grafana, the de-facto standard with k8s
 * Alertmanager, the de-facto standard with Prometheus
 * [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics) both for `kubectl top` and Prometheus
 * [node exporter](https://github.com/prometheus/node_exporter)
 * [Prometheus Operatior](https://github.com/coreos/prometheus-operator/) appears to be rock solid and the `ServiceMonitor` resources really delivers capabilities that service discovery base don annotations can't, such as scraping multiple containers and having custom intervals.

Dashboards:
 * Maybe https://github.com/cloudworkz/kube-eagle

Web UIs, as a complement:
 * https://srcco.de/posts/kubernetes-web-uis-in-2019.html
 * Can we have basic top + node health cheaply and independent of the stack?

Prometheus instances:

