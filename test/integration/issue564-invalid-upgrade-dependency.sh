#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue564-invalid-upgrade-dependency
rm -rf a-1.0.0/.dub
rm -rf a-1.1.0/.dub
rm -rf main/.dub
${DUB} build --bare --compiler=${DC} main
