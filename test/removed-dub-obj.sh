#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/removed-dub-obj
rm -rf .dub

${DUB} build --compiler=${DC}

[ -d ".dub/obj" ] && die $LINENO '.dub/obj was found'

if [[ ${DC} == *"ldc"* ]]; then
    [ -f .dub/build/library-*ldc*/obj/test.o* ] || die $LINENO '.dub/build/library-*ldc*/obj/test.o* was not found'
fi

exit 0