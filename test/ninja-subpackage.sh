#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd "$CURR_DIR"/ninja-subpackage

if ! $DUB generate ninja --compiler=$DC 2>&1; then
    die $LINENO 'dub generate ninja failed!'
fi

if ! grep -q "rule ar" build.ninja; then
    die $LINENO 'build.ninja missing ar rule!'
fi

if ! grep -q "\.a" build.ninja; then
    die $LINENO 'build.ninja missing static library build edge!'
fi

ninja -t clean
if ! ninja 2>&1; then
    die $LINENO 'ninja build failed!'
fi

if ! ./ninja-subpackage 2>&1; then
    die $LINENO 'linked executable failed to run!'
fi

ninja -t clean
rm -f build.ninja
