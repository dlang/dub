#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd ${CURR_DIR}/1-exec-simple
rm -f dub.selections.json
${DUB} clean
${DUB} build --compiler=${DC} 2>&1 | grep 'Building exec-simple ~master' -c
${DUB} build --compiler=${DC} 2>&1 | { ! grep 'Building exec-simple ~master' -c; }
