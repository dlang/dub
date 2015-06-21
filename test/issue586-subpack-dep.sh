#!/bin/sh

cd ${CURR_DIR}/issue586-subpack-dep
rm -rf a/.dub
rm -rf a/b/.dub
rm -rf c/.dub
${DUB} build --bare --compiler=${COMPILER} main || exit 1
${DUB} run --bare --compiler=${COMPILER} main || exit 1
