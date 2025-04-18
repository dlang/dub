#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd ${CURR_DIR}/issue1003-check-empty-ld-flags

# It should fail
! ${DUB} --root=${CURR_DIR}/issue1277/ build
