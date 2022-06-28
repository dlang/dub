#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh
DIR=$(dirname "${BASH_SOURCE[0]}")

cd "$DIR/unit_threaded-main"

# build and run the tests
$DUB test

# make sure the testrunner supports -l (to list the tests) and contains both unittests
if ! { ./unit_threaded-main-test-unittest -l | grep -q "modA.Unittest A"; } then
    die $LINENO 'modA unittest missing'
fi
if ! { ./unit_threaded-main-test-unittest -l | grep -q "modB.Unittest B"; } then
    die $LINENO 'modB unittest missing'
fi
