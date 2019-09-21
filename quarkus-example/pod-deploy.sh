#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -e

(cd app && mvn -Pjar clean package)
kubectl delete deploy demo-ystack-app
kubectl apply -k k8s/

sleep 5
set -x
kubectl logs -f -l app=demo-ystack-app
