#!/usr/bin/env bash

DIR=$(dirname "${BASH_SOURCE[0]}")

. "$DIR"/common.sh
cd ${CURR_DIR}/ninja-staticLibrary

function cleanup {
	rm -rf .dub/ninja/
    rm -rf build.ninja
	rm -rf libstaticlib-simple.a
}

trap cleanup EXIT
cleanup

$DUB generate ninja

if [ ! -f build.ninja ]; then
	die $LINENO 'Ninja file doesnt exist!'
fi

ninja

if [ ! -f libstaticlib-simple.a ]; then
	die $LINENO 'Static library doesnt exist!'
fi
