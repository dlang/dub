#!/usr/bin/env bash

DIR=$(dirname "${BASH_SOURCE[0]}")
. "$DIR"/common.sh

if [[ "$DC" != ldc* ]]; then
    echo "Skipping test, needs LDC"
    exit 0
fi

# enforce a full build (2 static libs, 1 dynamic one) and collect -v output
output=$("$DUB" build -v -f --root "$DIR"/dynLib-monolith)

if [[ $(grep -c -- '-fvisibility=hidden' <<<"$output") -ne 3 ]]; then
    die $LINENO "Didn't find 3 occurrences of '-fvisibility=hidden' in the verbose dub output!" "$output"
fi
