#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -e

IMAGE=solsson/demo-ystack-app:quarkus-dev
DOCKER_BUILDKIT=1 docker build -t $IMAGE -f app.Dockerfile .
docker push $IMAGE
