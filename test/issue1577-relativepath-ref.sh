#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue1577-relativepath-ref/foo

${DUB} remove -n --version=* dub 2>/dev/null || true
${DUB} build foo:sub
