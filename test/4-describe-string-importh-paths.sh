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

# Create the expected output path file to compare against.
echo "$CURR_DIR/describe-project/views/" > "$CURR_DIR/expected-string-import-path-output"
echo "$CURR_DIR/describe-dependency-2/some-extra-string-import-path/" >> "$CURR_DIR/expected-string-import-path-output"

if ! diff "$CURR_DIR"/expected-string-import-path-output "$temp_file"; then
    cleanup
    die 'The string import paths did not match the expected output!'
fi

cleanup
exit 0

