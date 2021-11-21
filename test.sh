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

# CI

# we should raise the bar here as soon as possible
DEFAULT_SHELLCHECK_LEVEL=error
[ -n "$SHELLCHECK_LEVEL" ] || SHELLCHECK_LEVEL=$DEFAULT_SHELLCHECK_LEVEL
echo "Running lint for level \"$SHELLCHECK_LEVEL\" ..."
y-shellcheck --severity=$SHELLCHECK_LEVEL $(git ls-tree -r HEAD --name-only -- ./bin/ | xargs awk '
  /^#!.*sh/{print FILENAME}
  {nextfile}')

# echo "Running bin specs ..."
# (cd bin && y-shellspec)

# What we think Docker Hub is running
set +e
BULID_EXIT_CODE_ON_NO_CLUSTER=1 GIT_COMMIT=$GIT_COMMIT docker-compose -f docker-compose.test.yml up --build --exit-code-from sut sut
RESULT=$?
docker-compose -f docker-compose.test.yml down --remove-orphans -v

echo "Result: $RESULT"
exit $RESULT
