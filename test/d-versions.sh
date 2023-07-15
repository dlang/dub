#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/d-versions
${DUB} build --d-version=FromCli1 --d-version=FromCli2
