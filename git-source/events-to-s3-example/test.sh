#!/bin/bash
set -e

NAMESPACE=ystack
GITEA_HOST=git.ystack.svc.cluster.local
GITEA_USER=ystack-admin
GITEA_PASS=ystack-admin-temp
GITEA_API="http://${GITEA_HOST}/api/v1"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "=== Step 1: Provision k3d cluster ==="
y-cluster-provision-k3d

echo "=== Step 2: Deploy Gitea base and install ==="
kubectl apply -k "$REPO_ROOT/git-source/base/"
kubectl apply -k "$REPO_ROOT/git-source/install/"

echo "=== Step 3: Wait for Gitea install job ==="
kubectl -n $NAMESPACE wait --for=condition=complete job/gitea-install --timeout=180s

echo "=== Step 4: Configure Gitea webhook settings ==="
# Allow webhook delivery to in-cluster services (private IPs)
kubectl -n $NAMESPACE exec gitea-0 -- sh -c '
  if ! grep -q "\\[webhook\\]" /data/gitea/conf/app.ini; then
    printf "\n[webhook]\nALLOWED_HOST_LIST = private\nDELIVER_TIMEOUT = 30\n" >> /data/gitea/conf/app.ini
    echo "Added webhook config to app.ini"
  else
    echo "Webhook config already present"
  fi
'
# Restart Gitea to pick up config changes
kubectl -n $NAMESPACE delete pod gitea-0
kubectl -n $NAMESPACE wait --for=condition=ready pod/gitea-0 --timeout=120s

echo "=== Step 5: Apply Gitea HTTPRoute ==="
kubectl -n $NAMESPACE apply -f "$SCRIPT_DIR/gitea-httproute.yaml"

echo "=== Step 6: Update ingress hosts ==="
y-k8s-ingress-hosts -write -override-ip "${YSTACK_PORTS_IP:-127.0.0.1}"

echo "=== Step 7: Create S3 bucket for events ==="
kubectl -n $NAMESPACE delete job bucket-create-gitea-events --ignore-not-found
kubectl -n $NAMESPACE apply -f "$SCRIPT_DIR/bucket-create-gitea-events.yaml"
kubectl -n $NAMESPACE wait --for=condition=complete job/bucket-create-gitea-events --timeout=120s

echo "=== Step 8: Deploy Envoy proxy and Fluent Bit ==="
kubectl -n $NAMESPACE apply -f "$SCRIPT_DIR/fluentbit-configmap.yaml"
kubectl -n $NAMESPACE apply -f "$SCRIPT_DIR/fluentbit-deployment.yaml"
kubectl -n $NAMESPACE apply -f "$SCRIPT_DIR/fluentbit-service.yaml"
kubectl -n $NAMESPACE rollout status deployment/fluentbit-webhook --timeout=120s

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
VERSITYGW_POD=$(kubectl -n $NAMESPACE get pod -l app=versitygw --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
echo "Checking versitygw pod: $VERSITYGW_POD"

EVENT_FILES=$(kubectl -n $NAMESPACE exec "$VERSITYGW_POD" -- find /data/gitea-events -type f 2>/dev/null || true)

if [ -z "$EVENT_FILES" ]; then
  echo "FAIL: No event files found in /data/gitea-events/"
  echo "Envoy logs:"
  kubectl -n $NAMESPACE logs deployment/fluentbit-webhook -c envoy --tail=20
  echo "Fluent Bit logs:"
  kubectl -n $NAMESPACE logs deployment/fluentbit-webhook -c fluent-bit --tail=20
  exit 1
fi

echo "SUCCESS: Found event files in S3 bucket:"
echo "$EVENT_FILES"

FILE_COUNT=$(echo "$EVENT_FILES" | wc -l | tr -d ' ')
echo "Total event files: $FILE_COUNT"

echo "=== Sample event content ==="
FIRST_FILE=$(echo "$EVENT_FILES" | head -1)
kubectl -n $NAMESPACE exec "$VERSITYGW_POD" -- cat "$FIRST_FILE" | head -c 500
echo ""

echo "=== Webhook delivery stats ==="
kubectl -n $NAMESPACE exec gitea-0 -- sqlite3 /data/gitea/gitea.db \
  "SELECT is_succeed, COUNT(*) FROM hook_task GROUP BY is_succeed;" 2>/dev/null || true

echo "=== Test passed ==="
