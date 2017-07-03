#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd ${CURR_DIR}/1-exec-simple
rm -f dub.selections.json
${DUB} build --compiler=${DC} 2>&1 | grep -e 'building configuration' -c
${DUB} build --compiler=${DC} 2>&1 | { ! grep -e 'building configuration' -c; }
