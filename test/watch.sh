#!/bin/bash

TEST_DIR=$(dirname $0)
echo 'enum count = 0;' > "$TEST_DIR"/watch/source/counter.d
# need force here, because the modtime change is too small
$DUB watch --root="$TEST_DIR"/watch --compiler=$COMPILER --force
