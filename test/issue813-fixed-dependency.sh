#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue813-fixed-dependency
rm -rf main/.dub
rm -rf sub/.dub
rm -rf sub/sub/.dub

echo "verify that we can build sub without add-local"
${DUB} build --compiler=${DC} --force --root=sub

rm -rf sub/.dub
rm -rf sub/sub/.dub

echo "verify that we can build sub with add-local"
${DUB} add-local sub
${DUB} build --compiler=${DC} --force --root=sub

${DUB} remove-local sub
rm -rf sub/.dub
rm -rf sub/sub/.dub

echo "verify that we can build main application"
${DUB} build --compiler=${DC} --root=main
