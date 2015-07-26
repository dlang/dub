#!/bin/bash
set -e -o pipefail

cd "$CURR_DIR"/issue616-describe-vs-generate-commands

temp_file=`mktemp`
temp_file2=`mktemp`

function cleanup {
    rm $temp_file
    rm $temp_file2
}

trap cleanup EXIT

if ! $DUB describe --data-list --data=target-name \
    > "$temp_file" 2>&1; then
    die 'Printing project data failed!'
fi

# Create the expected output file to compare stdout against.
expected_file="$CURR_DIR/expected-issue616-output"
echo "preGenerateCommands: DUB_PACKAGES_USED=issue616-describe-vs-generate-commands,issue616-subpack,issue616-subsubpack" > "$expected_file"
echo "$CURR_DIR/issue616-describe-vs-generate-commands/src/" >> "$expected_file"
echo "$CURR_DIR/issue616-subpack/src/" >> "$expected_file"
echo "$CURR_DIR/issue616-subsubpack/src/" >> "$expected_file"
echo "issue616-describe-vs-generate-commands" >> "$expected_file"

# Create the expected output file to compare stderr against.
expected_file2="$CURR_DIR/expected-issue616-output2"
echo "preGenerateCommands: DUB_PACKAGES_USED=issue616-describe-vs-generate-commands,issue616-subpack,issue616-subsubpack" > "$expected_file2"
echo "$CURR_DIR/issue616-describe-vs-generate-commands/src/" >> "$expected_file2"
echo "$CURR_DIR/issue616-subpack/src/" >> "$expected_file2"
echo "$CURR_DIR/issue616-subsubpack/src/" >> "$expected_file2"

if ! diff "$expected_file" "$temp_file"; then
    die 'The stdout output did not match the expected output!'
fi
