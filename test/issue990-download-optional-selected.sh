#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue990-download-optional-selected
${DUB} clean
${DUB} remove gitcompatibledubpackage -n 2>/dev/null || true
${DUB} run
