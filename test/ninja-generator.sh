#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd "$CURR_DIR"/ninja-generator

if ! $DUB generate ninja --compiler=$DC 2>&1; then
    die $LINENO 'dub generate ninja failed!'
fi

if [ ! -f build.ninja ]; then
    die $LINENO 'build.ninja was not generated!'
fi

if ! grep -q "rule dc" build.ninja; then
    die $LINENO 'build.ninja missing dc rule!'
fi

if ! grep -q "rule link" build.ninja; then
    die $LINENO 'build.ninja missing link rule!'
fi

ninja -t clean
if ! ninja 2>&1; then
    die $LINENO 'initial ninja build failed!'
fi

output1=$(./ninja-generator)
if [ "$output1" != "hello" ]; then
    die $LINENO "expected program output 'hello', got '$output1'"
fi

echo -n "world" > views/data.txt

if ! ninja 2>&1; then
    die $LINENO 'rebuild after data.txt change failed!'
fi

output2=$(./ninja-generator)
if [ "$output2" != "world" ]; then
    die $LINENO "expected program output 'world' after data.txt change, got '$output2'"
fi

echo -n "hello" > views/data.txt

ninja -t clean
rm -f build.ninja
