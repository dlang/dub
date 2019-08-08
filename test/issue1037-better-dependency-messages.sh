#!/usr/bin/env bash
set -e -o pipefail

cd ${CURR_DIR}/issue1037-better-dependency-messages

temp_file=$(mktemp $(basename $0).XXXXXX)
temp_file2=$(mktemp $(basename $0).XXXXXX)
expected_file="$CURR_DIR/expected-issue1037-output"

function cleanup {
    rm -f $temp_file
    rm -f $temp_file2
}

trap cleanup EXIT

sed "s#DIR#$CURR_DIR/issue1037-better-dependency-messages#" "$expected_file" > "$temp_file2"

$DUB upgrade 2>$temp_file && exit 1 # dub upgrade should fail

if ! diff "$temp_file2" "$temp_file"; then
    die $LINENO 'output not containing conflict information'
fi

exit 0
