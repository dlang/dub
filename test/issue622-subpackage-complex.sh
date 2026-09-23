#!/bin/sh

cd ${CURR_DIR}/issue622-subpackage-complex
rm -rf foo/.dub
rm -rf .dub
${DUB} build --compiler=${COMPILER} test:test || exit 1
${DUB} run --compiler=${COMPILER} test:test || exit 1
