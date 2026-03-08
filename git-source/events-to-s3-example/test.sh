#!/bin/bash
[ -z "$DEBUG" ] || set -x
set -eo pipefail

NAMESPACE=ystack
GITEA_HOST=git.ystack.svc.cluster.local
GITEA_USER=ystack-admin
GITEA_PASS=ystack-admin-temp
GITEA_API="http://${GITEA_HOST}/api/v1"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

k() {
  kubectl --context=local -n "$NAMESPACE" "$@"
}

echo "=== Step 1: Provision k3d cluster ==="
y-cluster-provision-k3d

echo "=== Step 2: Deploy Gitea ==="
k apply -k "$REPO_ROOT/git-source/base/"
k apply -k "$REPO_ROOT/git-source/install/"

echo "=== Step 3: Wait for Gitea install ==="
k wait --for=condition=complete job/gitea-install --timeout=180s

echo "=== Step 4: Configure Gitea webhook settings ==="
# Allow webhook delivery to in-cluster services (private IPs)
k exec gitea-0 -- sh -c '
  if ! grep -q "\[webhook\]" /etc/gitea/app.ini; then
    printf "\n[webhook]\nALLOWED_HOST_LIST = private\nDELIVER_TIMEOUT = 30\n" >> /etc/gitea/app.ini
    echo "Added webhook config to app.ini"
  else
    echo "Webhook config already present"
  fi
'
# Restart Gitea to pick up config changes
k delete pod gitea-0
k wait --for=condition=ready pod/gitea-0 --timeout=120s

echo "=== Step 5: Apply Gitea HTTPRoute ==="
k apply -f "$SCRIPT_DIR/gitea-httproute.yaml"

echo "=== Step 6: Update ingress hosts ==="
y-k8s-ingress-hosts -write -override-ip "${YSTACK_PORTS_IP:-127.0.0.1}"

echo "=== Step 7: Create S3 bucket for events ==="
k delete job bucket-create-gitea-events --ignore-not-found
k apply -f "$SCRIPT_DIR/bucket-create-gitea-events.yaml"
k wait --for=condition=complete job/bucket-create-gitea-events --timeout=120s

echo "=== Step 8: Deploy Fluent Bit webhook receiver ==="
k apply -f "$SCRIPT_DIR/fluentbit-configmap.yaml"
k apply -f "$SCRIPT_DIR/fluentbit-deployment.yaml"
k apply -f "$SCRIPT_DIR/fluentbit-service.yaml"
k rollout status deployment/fluentbit-webhook --timeout=120s

echo "=== Step 9: Wait for Gitea API ==="
for i in $(seq 1 30); do
  if curl -sf -o /dev/null "$GITEA_API/version"; then
    echo "Gitea API is ready"
    break
  fi
  [ $i -eq 30 ] && echo "Gitea API did not become ready" && exit 1
  sleep 2
done

echo "=== Step 10: Create test repos ==="
for REPO in test-repo-1 test-repo-2; do
  curl -sf -u "$GITEA_USER:$GITEA_PASS" \
    -X POST "$GITEA_API/user/repos" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$REPO\",\"auto_init\":true}" \
    -o /dev/null
  echo "Created repo $REPO"
done

echo "=== Step 11: Create webhooks ==="
for REPO in test-repo-1 test-repo-2; do
  curl -sf -u "$GITEA_USER:$GITEA_PASS" \
    -X POST "$GITEA_API/repos/$GITEA_USER/$REPO/hooks" \
    -H "Content-Type: application/json" \
    -d '{
      "type": "gitea",
      "config": {
        "url": "http://fluentbit-webhook:9880/gitea",
        "content_type": "json"
      },
      "events": ["push", "pull_request", "issues"],
      "active": true
    }' \
    -o /dev/null
  echo "Created webhook for $REPO"
done

echo "=== Step 12: Generate events ==="
for REPO in test-repo-1 test-repo-2; do
  CLONE_DIR="$TMPDIR/$REPO"
  CLONE_URL="http://${GITEA_USER}:${GITEA_PASS}@${GITEA_HOST}/${GITEA_USER}/${REPO}.git"

  git clone "$CLONE_URL" "$CLONE_DIR"
  cd "$CLONE_DIR"
  git config user.email "test@example.com"
  git config user.name "Test"

  # Push a commit to main
  echo "change-$(date +%s)" > testfile.txt
  git add testfile.txt
  git commit -m "test commit on main"
  git push origin main

  # Create feature branch and push
  git checkout -b feature-branch
  echo "feature-$(date +%s)" > feature.txt
  git add feature.txt
  git commit -m "feature branch commit"
  git push origin feature-branch

  # Create pull request
  PR_RESPONSE=$(curl -sf -u "$GITEA_USER:$GITEA_PASS" \
    -X POST "$GITEA_API/repos/$GITEA_USER/$REPO/pulls" \
    -H "Content-Type: application/json" \
    -d '{"title":"Test PR","head":"feature-branch","base":"main"}')
  PR_NUMBER=$(echo "$PR_RESPONSE" | grep -o '"number":[0-9]*' | grep -o '[0-9]*')
  echo "Created PR #$PR_NUMBER in $REPO"

  # Create label
  LABEL_RESPONSE=$(curl -sf -u "$GITEA_USER:$GITEA_PASS" \
    -X POST "$GITEA_API/repos/$GITEA_USER/$REPO/labels" \
    -H "Content-Type: application/json" \
    -d '{"name":"test-label","color":"#00aabb"}')
  LABEL_ID=$(echo "$LABEL_RESPONSE" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
  echo "Created label id=$LABEL_ID in $REPO"

  # Apply label to PR (PRs are issues in Gitea)
  curl -sf -u "$GITEA_USER:$GITEA_PASS" \
    -X POST "$GITEA_API/repos/$GITEA_USER/$REPO/issues/$PR_NUMBER/labels" \
    -H "Content-Type: application/json" \
    -d "{\"labels\":[$LABEL_ID]}" \
    -o /dev/null
  echo "Applied label to PR #$PR_NUMBER in $REPO"

  cd "$TMPDIR"
done

echo "=== Step 13: Wait for Fluent Bit to flush ==="
sleep 25

echo "=== Step 14: Verify events in S3 ==="
VERSITYGW_POD=$(k get pod -l app=versitygw --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
echo "Checking versitygw pod: $VERSITYGW_POD"

EVENT_FILES=$(k exec "$VERSITYGW_POD" -- find /data/gitea-events -type f 2>/dev/null || true)

if [ -z "$EVENT_FILES" ]; then
  echo "FAIL: No event files found in /data/gitea-events/"
  echo "Fluent Bit logs:"
  k logs deployment/fluentbit-webhook --tail=30
  exit 1
fi

echo "SUCCESS: Found event files in S3 bucket:"
echo "$EVENT_FILES"

FILE_COUNT=$(echo "$EVENT_FILES" | wc -l | tr -d ' ')
echo "Total event files: $FILE_COUNT"

echo "=== Sample event content ==="
FIRST_FILE=$(echo "$EVENT_FILES" | head -1)
k exec "$VERSITYGW_POD" -- cat "$FIRST_FILE" | head -c 500
echo ""

echo "=== Test passed ==="
