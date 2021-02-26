#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -eo pipefail

# https://github.com/Yolean/build-contract/blob/a7e1a96ccec79bf413d604c344679f7439c34b49/build-contract#L21
GIT_COMMIT=$(git rev-parse --verify HEAD 2>/dev/null || echo '')
if [[ ! -z "$GIT_COMMIT" ]]; then
  GIT_STATUS=$(git status --untracked-files=no --porcelain=v2)
  if [[ ! -z "$GIT_STATUS" ]]; then
    GIT_COMMIT="$GIT_COMMIT-dirty"
  fi
fi

# What we think Docker Hub is running
BULID_EXIT_CODE_ON_NO_CLUSTER=1 GIT_COMMIT=$GIT_COMMIT docker-compose -f docker-compose.test.yml up --build --exit-code-from sut --scale node=1 sut
RESULT=$?
docker-compose -f docker-compose.test.yml down --remove-orphans -v

echo "Result: $RESULT"
exit $RESULT
