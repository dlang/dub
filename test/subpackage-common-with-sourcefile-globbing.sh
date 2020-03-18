#!/bin/sh
set -e

cd ${CURR_DIR}/subpackage-common-with-sourcefile-globbing
rm -rf .dub dub.selections.json
${DUB} build --compiler=${DC} :server -v
${DUB} build --compiler=${DC} :client -v
${DUB} build --compiler=${DC} :common -v
