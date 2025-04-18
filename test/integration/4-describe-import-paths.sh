#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd "$CURR_DIR"/describe-project

temp_file=$(mktemp $(basename $0).XXXXXX)

function cleanup {
    rm $temp_file
}

trap cleanup EXIT

if ! $DUB describe --compiler=$DC --import-paths > "$temp_file"; then
    die $LINENO 'Printing import paths failed!'
fi

# Create the expected output path file to compare against.
echo "$CURR_DIR/describe-project/src/" > "$CURR_DIR/expected-import-path-output"
echo "$CURR_DIR/describe-dependency-1/source/" >> "$CURR_DIR/expected-import-path-output"
echo "$CURR_DIR/describe-dependency-2/some-path/" >> "$CURR_DIR/expected-import-path-output"
echo "$CURR_DIR/describe-dependency-3/dep3-source/" >> "$CURR_DIR/expected-import-path-output"

if ! diff "$CURR_DIR"/expected-import-path-output "$temp_file"; then
    die $LINENO 'The import paths did not match the expected output!'
fi

