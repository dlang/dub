#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/removed-dub-obj

DUB_CACHE_PATH="$HOME/.dub/cache/removed-dub-obj/"

rm -rf $DUB_CACHE_PATH

${DUB} build --compiler=${DC}

[ -d "$DUB_CACHE_PATH/obj" ] && die $LINENO "$DUB_CACHE_PATH/obj was found"

if [[ ${DC} == *"ldc"* ]]; then
    if [ ! -f $DUB_CACHE_PATH/~master/build/library-*/obj/test.o* ]; then
        ls -lR $DUB_CACHE_PATH
        die $LINENO '$DUB_CACHE_PATH/~master/build/library-*/obj/test.o* was not found'
    fi
fi

exit 0
