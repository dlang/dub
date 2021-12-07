#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd "$CURR_DIR"/describe-project

temp_file=$(mktemp $(basename $0).XXXXXX)
settings_file="$CURR_DIR/describe-project/dub.settings.json"

echo '{
    "defaultEnvironments": {
        "TestEnv": "Value"
    }
}' > "$settings_file"

function cleanup {
    rm $settings_file
    rm $temp_file
}

trap cleanup EXIT

if ! $DUB describe --compiler=$DC \
    --filter-versions -d=customDebugVersion -b=custombuild --build-mode=allAtOnce \
    --data-list \
    --data=environments \
    --data=debug-versions \
    --data=libs \
    --data=options \
    > "$temp_file"; then
    die $LINENO 'Printing project data failed!'
fi

# Create the expected output path file to compare against.
expected_file="$CURR_DIR/expected-describe-with-cli-data-list-output"
# --data=environments
echo "TestEnv=Value" > "$expected_file"
echo >> "$expected_file"
# --data=debug-versions
echo "someDebugVerIdent" >> "$expected_file"
echo "anotherDebugVerIdent" >> "$expected_file"
echo "customDebugVersion" >> "$expected_file"
echo >> "$expected_file"
# --data=libs
echo "somelib" >> "$expected_file"
echo "anotherlib" >> "$expected_file"
echo "customlib" >> "$expected_file"
echo >> "$expected_file"
# --data=options
echo "releaseMode" >> "$expected_file"
echo "debugInfo" >> "$expected_file"
echo "warnings" >> "$expected_file"
echo "deprecationErrors" >> "$expected_file"
echo "betterC" >> "$expected_file"

if ! diff "$expected_file" "$temp_file"; then
    die $LINENO 'The project data did not match the expected output!'
fi

