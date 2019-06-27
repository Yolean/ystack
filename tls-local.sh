#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -e

[ -z "$CERT_PATH" ] && CERT_PATH="$(dirname $0)/ingress-tls-local"

INGRESS_HOSTS=$(kubectl get ingress --all-namespaces -o=jsonpath='{range .items[*].spec.rules[*]}{.host}{" "}{end}')

case "$INGRESS_HOSTS" in
  *[![:blank:]]*) ;;
  *) echo 'No ingress hosts found. Aborting cert run.' && exit 1 ;;
esac

echo "Ingress hosts found: $INGRESS_HOSTS"

mkcert -cert-file "$CERT_PATH/tls.crt" -key-file "$CERT_PATH/tls.key" -p12-file "$CERT_PATH/tls.p12" $INGRESS_HOSTS
