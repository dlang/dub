#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd ${CURR_DIR}/issue1003-check-empty-ld-flags

${DUB} build --compiler=${DC} --force
