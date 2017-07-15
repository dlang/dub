#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue990-download-optional-selected
rm -rf b/.dub
${DUB} remove gitcompatibledubpackage -n --version=* 2>/dev/null || true
${DUB} run
