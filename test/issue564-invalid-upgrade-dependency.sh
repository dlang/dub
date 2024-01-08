#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue564-invalid-upgrade-dependency
${DUB} build -f --bare --compiler=${DC} main
