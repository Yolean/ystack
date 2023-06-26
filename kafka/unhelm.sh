#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -eo pipefail

UNHELM_REF=a3addefaa4a1213342b7d499e7b801ecf23189d2

curl -sLS "https://raw.githubusercontent.com/Yolean/unhelm/$UNHELM_REF/unhelm.sh" | bash -s -- $@
