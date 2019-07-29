# See ./installer for a more encapsulated approach

# https://github.com/knative/docs/blob/master/docs/install/Knative-custom-install.md

kubectl apply -k github.com/Yolean/unhelm/istio/crds?ref=390bdbc6bfd03bd09edbf271afe466f09e8d4a6e
sleep 5
kubectl apply -k github.com/Yolean/unhelm/istio/namespace?ref=390bdbc6bfd03bd09edbf271afe466f09e8d4a6e
kubectl apply -f https://github.com/Yolean/unhelm/raw/390bdbc6bfd03bd09edbf271afe466f09e8d4a6e/istio/knative-istio-lean.yaml

kubectl apply --selector knative.dev/crd-install=true \
  --filename https://github.com/knative/serving/releases/download/v0.7.1/serving.yaml \
  --filename https://github.com/knative/eventing/releases/download/v0.7.1/release.yaml \
  --filename https://github.com/knative/serving/releases/download/v0.7.1/monitoring-metrics-prometheus.yaml \
  --filename https://github.com/knative/eventing/releases/download/v0.7.1/kafka.yaml

kubectl apply \
  --filename https://github.com/knative/serving/releases/download/v0.7.1/serving.yaml \
  --filename https://github.com/knative/eventing/releases/download/v0.7.1/release.yaml \
  --filename https://github.com/knative/serving/releases/download/v0.7.1/monitoring-metrics-prometheus.yaml \
  --filename https://github.com/knative/eventing/releases/download/v0.7.1/kafka.yaml
