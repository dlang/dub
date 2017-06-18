#!/bin/bash
set -e -o pipefail

cd ${CURR_DIR}/issue1037-better-dependency-messages

temp_file=$(mktemp $(basename $0).XXXXXX)
expected_file="$CURR_DIR/expected-issue1037-output"

function cleanup {
    rm $temp_file
}

trap cleanup EXIT

$DUB upgrade 2>$temp_file && exit 1 # dub upgrade should fail

if ! diff "$expected_file" "$temp_file"; then
    die 'output not containing conflict information'
fi

exit 0