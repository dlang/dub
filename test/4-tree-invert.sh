#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd "$CURR_DIR"/tree-project

temp_file=$(mktemp $(basename $0).XXXXXX)

function cleanup {
    rm $temp_file
}

trap cleanup EXIT

if ! $DUB tree --compiler=$DC --invert=dep-b > "$temp_file"; then
    die $LINENO 'Printing inverted dependency tree failed!'
fi

# Normalize line endings and path separators so that the checks work on Windows, too.
sed -i 's/\r//; s|\\|/|g' $temp_file

# Create the expected output to compare against.
echo "dep-b 1.0.0 $CURR_DIR/tree-project/dep-b/" > "$CURR_DIR"/expected-tree-invert-output
echo "├─ dep-a 1.0.0 $CURR_DIR/tree-project/dep-a/" >> "$CURR_DIR"/expected-tree-invert-output
echo "│  └─ tree-project 1.0.0 $CURR_DIR/tree-project/" >> "$CURR_DIR"/expected-tree-invert-output
echo "└─ tree-project 1.0.0 $CURR_DIR/tree-project/" >> "$CURR_DIR"/expected-tree-invert-output

if ! diff "$CURR_DIR"/expected-tree-invert-output "$temp_file"; then
    die $LINENO 'The inverted dependency tree did not match the expected output!'
fi

rm "$CURR_DIR"/expected-tree-invert-output

if $DUB tree --compiler=$DC --invert=no-such-package > /dev/null 2>&1; then
    die $LINENO 'Inverting a tree for an unknown package should have failed!'
fi
