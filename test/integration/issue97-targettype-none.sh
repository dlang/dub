#!/usr/bin/env bash
set -e

${DUB} build --root ${CURR_DIR}/issue97-targettype-none 2>&1 || true

BUILD_CACHE_A="$HOME/.dub/cache/issue97-targettype-none/~master/+a/build/"
BUILD_CACHE_B="$HOME/.dub/cache/issue97-targettype-none/~master/+b/build/"

if [ ! -d $BUILD_CACHE_A ]; then
    echo "Generated 'a' subpackage build artifact not found!" 1>&2
    exit 1
fi
if [ ! -d $BUILD_CACHE_B ]; then
    echo "Generated 'b' subpackage build artifact not found!" 1>&2
    exit 1
fi

${DUB} clean --root ${CURR_DIR}/issue97-targettype-none 2>&1

# make sure both sub-packages are cleaned
if [ -d $BUILD_CACHE_A ]; then
    echo "Generated 'a' subpackage build artifact were not cleaned!" 1>&2
    exit 1
fi
if [ -d $BUILD_CACHE_B ]; then
    echo "Generated 'b' subpackage build artifact were not cleaned!" 1>&2
    exit 1
fi
