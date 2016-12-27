#!/bin/sh

cd ${CURR_DIR}/issue934-path-dep
rm -rf main/.dub
rm -rf a/.dub
rm -rf b/.dub
rm -f main/dub.selections.json
cd main
${DUB} build --compiler=${DC} || exit 1
