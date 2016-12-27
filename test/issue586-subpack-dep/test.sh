#!/bin/sh

cd ${CURR_DIR}/issue586-subpack-dep
rm -rf a/.dub
rm -rf a/b/.dub
rm -rf main/.dub
${DUB} build --bare --compiler=${DC} main || exit 1
${DUB} run --bare --compiler=${DC} main || exit 1
