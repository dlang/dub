#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue1004-override-config
${DUB} build --bare main --override-config a/success || exit 1
