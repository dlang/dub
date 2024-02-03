#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue813-pure-sub-dependency
rm -f main/~master/main/dub.selections.json
${DUB} build -f --bare --compiler=${DC} main
