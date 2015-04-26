#!/bin/bash

cd "$CURR_DIR"/describe-project

temp_file=`mktemp`

function cleanup {
    rm $temp_file
}

$DUB describe --compiler=$COMPILER --import-paths > "$temp_file"

if (( $? )); then
    cleanup
    die 'Printing import paths failed!'
fi

if ! diff "$CURR_DIR"/expected-import-path-output "$temp_file"; then
    cleanup
    die 'The import paths did not match the expected output!'
fi

cleanup
exit 0
