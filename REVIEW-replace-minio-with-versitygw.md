# Review: replace-minio-with-versitygw branch

## Summary

This branch replaces Minio with [VersityGW](https://github.com/versity/versitygw) as the S3-compatible object store backing the container image registry in ystack's k3s/k3d provisioning.

Three commits implement the change:

1. **7fe2cfa** - Add versitygw kustomize bases and registry overlay
2. **fcbb591** - Switch bucket-create job from aws-cli to minio/mc (smaller image)
3. **12ff78f** - Update Dockerfile, entrypoint.sh, buildkit, and docker-compose to reference versitygw

## Architecture

VersityGW replaces Minio while preserving the same S3 API contract:

```
registry (docker-v2) --S3--> blobs-versitygw:80 --> versitygw:7070 --> PVC (posix /data)
```

- **Image**: `versity/versitygw:latest` (currently v1.2.0)
- **Backend**: POSIX filesystem on a 10Gi PVC
- **Port**: 7070 internally, exposed as port 80 via `blobs-versitygw` service
- **Credentials**: Reuses the existing `minio` secret name for backward compatibility

## Validation Results

### Provisioning test (bin/y-cluster-provision-k3d)

| Step | Result |
|------|--------|
| k3d cluster create | PASS |
| 00-ystack-namespace apply | PASS |
| 10-versitygw apply | PASS |
| 20-builds-registry-versitygw apply | PASS (after image tag fix) |
| 21-prod-registry apply | PASS |
| 40-buildkit apply | PASS |
| versitygw pod ready | PASS |
| bucket-create job complete | PASS |
| registry pod ready | PASS |

### Blob persistence test

| Step | Result |
|------|--------|
| Upload test blobs to versitygw | PASS |
| `mc ls --recursive` shows 2 files | PASS |
| `kubectl rollout restart deployment/versitygw` | PASS |
| New pod starts (different pod name confirms restart) | PASS |
| Blobs verified present after restart via `mc ls` | PASS |
| Blob content verified via `mc cat` | PASS |

Blobs survive versitygw restart because the PVC persists across pod replacements.

## Issues Found

### Bug: Invalid minio/mc image tag

**File**: `registry/generic,versitygw/bucket-create-ystack-builds.yaml:10`

The image tag `minio/mc:RELEASE.2025-02-08T13-51-10Z` does not exist on Docker Hub.
The closest available tag is `RELEASE.2025-02-08T19-14-21Z`.

This causes `ImagePullBackOff` during provisioning, preventing the bucket from being created and leaving the registry in a 503 state until manually fixed.

**Fixed in this review commit.**

### Observations

1. **`versity/versitygw:latest` tag** - Using `:latest` without a digest makes builds non-reproducible. The running version at test time was v1.2.0. Consider pinning to a specific tag (e.g. `versity/versitygw:v1.2.0`) or adding a digest.

2. **Deprecated kustomize fields** - Multiple kustomization.yaml files use `bases:` and `patchesStrategicMerge:` which emit deprecation warnings. These should use `resources:` and `patches:` respectively. This is pre-existing across the codebase, not introduced by this branch.

3. **Secret naming** - The secret is still named `minio` despite no longer using Minio. This works for backward compatibility but could be confusing. A rename would require coordinating across versitygw deployment, registry deployment, and bucket-create job.

4. **Race condition: registry vs bucket-create** - The registry returns 503 until the bucket exists. The bucket-create job sleeps 30s then creates the bucket. During provisioning this means the registry is unhealthy for ~30-40 seconds. The old minio config had the same pattern. This is acceptable for provisioning but worth noting.

5. **buildkit base references versitygw** - `k3s/40-buildkit/kustomization.yaml` bases on `versitygw/standalone,defaultsecret`, creating a second reference to the same versitygw deployment. Kustomize deduplicates this (`unchanged` in apply output), but the dependency is implicit.

6. **No resource requests/limits** on versitygw deployment - The pod runs without CPU/memory requests or limits.

## New utility: bin/y-cluster-blobs-ls

A utility script was created to recursively list blob store contents:

```bash
# List all buckets
y-cluster-blobs-ls --context=local

# List contents of a specific bucket recursively
y-cluster-blobs-ls --context=local ystack-builds-registry
```

The script follows ystack conventions: requires `--context=local` as the first argument (only "local" is accepted), and passes it through to kubectl. It reads S3 credentials from the `minio` secret and runs a temporary `minio/mc` pod in the cluster.

## Verdict

The migration is functionally correct after the image tag fix. VersityGW works as a drop-in S3-compatible replacement for Minio with the POSIX backend providing simple, PVC-backed persistence. The main blocker was the invalid minio/mc image tag which has been corrected.
