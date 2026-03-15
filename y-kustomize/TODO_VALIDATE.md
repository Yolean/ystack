# y-kustomize validation

## Design

The `y-kustomize/openapi/` directory is a kustomize base that produces:

1. A Secret `y-kustomize-openapi` containing:
   - `openapi.yaml` — the OpenAPI 3.1 spec
   - `validate.sh` — a test script

2. A Job `y-kustomize-openapitest` using
   `ghcr.io/yolean/curl-yq:387f24cd8a6098c1dafcdb4e5fd368b13af65ca3`
   that runs `validate.sh`.

## SWS hosting

The `y-kustomize-openapi` secret is mounted as an optional volume in the
SWS deployment, serving the spec at a discovery path such as
`/openapi.yaml`.

## Validation script

The script:

1. Waits for the openapi spec to be available at the discovery URL,
   confirming y-kustomize is serving and the spec secret is mounted.
2. Parses the spec with `yq` to extract all paths.
3. For each `get` endpoint in the spec:
   - Fetches the URL and asserts HTTP 200.
   - For `base-for-annotations.yaml` endpoints, validates that the
     response parses as YAML and contains expected resource kinds
     (Secret, Job).
4. Reports pass/fail per endpoint.

Endpoints backed by optional secrets that are not yet created (e.g.
`/v1/kafka/setup-topic-job/base-for-annotations.yaml` before kafka is
installed) are expected to return 404 and should not fail the test.

## Converge integration

Add after the `09-y-kustomize` step in `y-cluster-converge-ystack`:

```bash
apply_base 09-y-kustomize-openapitest
k -n ystack wait job/y-kustomize-openapitest --for=condition=complete --timeout=60s
echo "# Validated: y-kustomize API spec test passed"
```

This runs before any consumer (like `10-versitygw` or
`20-builds-registry-versitygw`) depends on y-kustomize.

After `10-versitygw` creates the blobs secret and y-kustomize picks it
up, the test could optionally run again to validate the newly available
endpoint. This is not yet designed.

## TODO

- [ ] Create `y-kustomize/openapi/validate.sh`
- [ ] Create `y-kustomize/openapi/kustomization.yaml` with secretGenerator
      and Job resource
- [ ] Add `y-kustomize-openapi` volume mount to `y-kustomize/deployment.yaml`
- [ ] Add `k3s/09-y-kustomize-openapitest/` referencing the openapi base
- [ ] Add the converge step
