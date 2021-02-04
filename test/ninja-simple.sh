#!/usr/bin/env bash

DIR=$(dirname "${BASH_SOURCE[0]}")

. "$DIR"/common.sh
cd ${CURR_DIR}/ninja-simple

function cleanup {
    rm -rf build.ninja
	rm -rf exec-simple
}

trap cleanup EXIT
cleanup

$DUB generate ninja

if [ ! -f build.ninja ]; then
	die $LINENO 'Ninja file doesnt exist!'
fi

ninja

if [ ! -f exec-simple ]; then
	die $LINENO 'Executable file doesnt exist!'
fi

if [ "$(./exec-simple)" != "Hello from ninja!" ]; then
	die $LINENO 'Cant run executable correctly'
fi
