#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -e

# Needed until Skaffold supports buildctl, or the buildkit that comes with Docker supports BUILDKIT_HOST
# We could also build usinig Tekton, if Skaffold had a generic way to transfer the build context to a waitinig build step container

# Settings
BUILDKIT_NAMESPACE=buildkit
REGISTRY=builds.registry.svc.cluster.local
BUILDCTL_VERSION="buildctl github.com/moby/buildkit v0.5.1 646fc0af6d283397b9e47cd0a18779e9d0376e0e"
[ "$(buildctl -v)" != "$BUILDCTL_VERSION"  ] && echo "Requires buildctl '$BUILDCTL_VERSION'; see https://github.com/moby/buildkit/releases" && exit 1

# Envs from Skaffold build custom
# (but for now we simply ignore PUSH_IMAGE as it has no clear significance for in-cluster builds)
[ -z "$BUILD_CONTEXT" ] && echo "Expected a BUILD_CONTEXT env from Skaffold" && exit 1
[ -z "$IMAGES" ] && echo "Expected an IMAGES env from Skaffold" && exit 1
[ "$(echo $IMAGES | wc -w)" != "       1" ]  && echo "Currently we only support one entry in \$IMAGES" && exit 1

# Find an available BUILDKIT_HOST
BUILDERS=$(kubectl --kubeconfig=$KUBECONFIG -n $BUILDKIT_NAMESPACE get pods --field-selector=status.phase=Running -o=jsonpath='{.items[*].metadata.name}')
[ -z "$BUILDERS" ] && echo "Failed to find ready builders in $BUILDKIT_NAMESPACE" && exit 1
[ "$(echo $BUILDERS | wc -w)" != "       1" ]  && echo "Found >1 builders and we have no logic for that yet: $BUILDERS" && exit 1
export BUILDKIT_HOST="kube-pod://buildkitd-0?context=$KUBE_CONTEXT&namespace=$BUILDKIT_NAMESPACE&container=buildkitd"

IMAGE=$IMAGES
case "$IMAGE" in
  $REGISTRY/* ) ;;
  * ) echo "Only the ystack builds registry is supported at the moment. Got: $IMAGE" && exit 1 ;;
esac

OUTPUT="type=image,name=$IMAGE,push=true,registry.insecure=true"

if ! [ "$(curl -s http://$builds.registry.svc.cluster.local/v2/)" != "{}" ]
then
  echo "Skaffold need local access to the builds registry for digest lookup after build"
  echo "Look for ystacks's ingress or port-forward utilities"
  exit 1
fi

echo "Build command:"
set -x
KUBECONFIG=$KUBECONFIG buildctl build \
    --frontend dockerfile.v0 \
    --local context="$BUILD_CONTEXT" \
    --local dockerfile="$BUILD_CONTEXT" \
    --opt filename=$FILENAME \
    --output "$OUTPUT"
