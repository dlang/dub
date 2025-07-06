#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd ${CURR_DIR}/dest-directory
rm -rf .dub
rm -rf testout/

${DUB} build --dest=testout/
if ! [ -d testout/ ]; then
    die $LINENO 'Failed to stage into testout/'
fi