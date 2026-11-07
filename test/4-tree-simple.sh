#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd "$CURR_DIR"/tree-project

temp_file=$(mktemp $(basename $0).XXXXXX)

function cleanup {
    rm $temp_file
}

trap cleanup EXIT

if ! $DUB tree --compiler=$DC > "$temp_file"; then
    die $LINENO 'Printing dependency tree failed!'
fi

# Normalize line endings and path separators so that the checks work on Windows, too.
sed -i 's/\r//; s|\\|/|g' $temp_file

# Create the expected output to compare against.
echo "tree-project 1.0.0 $CURR_DIR/tree-project/" > "$CURR_DIR"/expected-tree-output
echo "├─ dep-a 1.0.0 $CURR_DIR/tree-project/dep-a/" >> "$CURR_DIR"/expected-tree-output
echo "│  └─ dep-b 1.0.0 $CURR_DIR/tree-project/dep-b/" >> "$CURR_DIR"/expected-tree-output
echo "└─ dep-b 1.0.0 $CURR_DIR/tree-project/dep-b/" >> "$CURR_DIR"/expected-tree-output

if ! diff "$CURR_DIR"/expected-tree-output "$temp_file"; then
    die $LINENO 'The dependency tree did not match the expected output!'
fi

rm "$CURR_DIR"/expected-tree-output
