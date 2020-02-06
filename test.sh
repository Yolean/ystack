#!/bin/bash

# What we think Docker Hub is running
BULID_EXIT_CODE_ON_NO_CLUSTER=1 docker-compose -f docker-compose.test.yml up --build --exit-code-from sut --scale node=1 sut
RESULT=$?
docker-compose -f docker-compose.test.yml down --remove-orphans -v

echo "Result: $RESULT"
exit $RESULT
