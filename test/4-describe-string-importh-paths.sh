#!/bin/bash

cd "$CURR_DIR"/describe-project

temp_file=`mktemp`

function cleanup {
    rm $temp_file
}

$DUB describe --compiler=$COMPILER --string-import-paths > "$temp_file"

if (( $? )); then
    cleanup
    die 'Printing string import paths failed!'
fi

if ! diff -q "$CURR_DIR"/expected-string-import-path-output "$temp_file"; then
    cleanup
    die 'The string import paths did not match the expected output!'
fi

cleanup
exit 0

