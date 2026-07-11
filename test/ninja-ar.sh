#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd "$CURR_DIR"/ninja-static-lib

if ! $DUB generate ninja --compiler=$DC 2>&1; then
    die $LINENO 'dub generate ninja failed!'
fi

ninja -t clean
if ! ninja 2>&1; then
    die $LINENO 'ninja build failed!'
fi

if [ ! -f ninja-static-lib.a ]; then
    die $LINENO 'static library was not produced!'
fi

$DC -c consumer.d -of=consumer.o
$DC consumer.o ninja-static-lib.a -of=consumer_test

output=$(./consumer_test)
if [ "$output" != "5" ]; then
    die $LINENO "expected 5 from linked archive, got '$output'"
fi

rm -f consumer.o consumer_test
ninja -t clean
rm -f build.ninja
