#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue586-subpack-dep
rm -rf a/.dub
rm -rf a/b/.dub
rm -rf main/.dub
${DUB} build --bare --compiler=${DC} main
${DUB} run --bare --compiler=${DC} main
