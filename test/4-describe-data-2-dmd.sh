#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

if [ "${DC}" != "dmd" ]; then
    echo Skipping DMD-centric test on configuration that lacks DMD.
    exit
fi

cd "$CURR_DIR"/describe-project

temp_file=$(mktemp $(basename $0).XXXXXX)

function cleanup {
    rm $temp_file
}

trap cleanup EXIT

if ! $DUB describe --compiler=$DC --filter-versions \
    --data=main-source-file \
    --data=dflags,lflags \
    --data=libs,linker-files \
    --data=source-files \
    --data=versions \
    --data=debug-versions \
    --data=import-paths \
    --data=string-import-paths \
    --data=import-files \
    --data=options \
    > "$temp_file"; then
    die $LINENO 'Printing project data failed!'
fi

# Create the expected output path file to compare against.
expected_file="$CURR_DIR/expected-describe-data-2-dmd-output"
# --data=main-source-file
echo -n "'$CURR_DIR/describe-project/src/dummy.d' " > "$expected_file"
# --data=dflags
echo -n "--some-dflag " >> "$expected_file"
echo -n "--another-dflag " >> "$expected_file"
# --data=lflags
echo -n "-L--some-lflag " >> "$expected_file"
echo -n "-L--another-lflag " >> "$expected_file"
# --data=libs
echo -n "-L-lsomelib " >> "$expected_file"
echo -n "-L-lanotherlib " >> "$expected_file"
# --data=linker-files
echo -n "'$CURR_DIR/describe-dependency-3/libdescribe-dependency-3.a' " >> "$expected_file"
echo -n "'$CURR_DIR/describe-project/some.a' " >> "$expected_file"
echo -n "'$CURR_DIR/describe-dependency-1/dep.a' " >> "$expected_file"
# --data=source-files
echo -n "'$CURR_DIR/describe-project/src/dummy.d' " >> "$expected_file"
echo -n "'$CURR_DIR/describe-dependency-1/source/dummy.d' " >> "$expected_file"
# --data=versions
echo -n "-version=someVerIdent " >> "$expected_file"
echo -n "-version=anotherVerIdent " >> "$expected_file"
echo -n "-version=Have_describe_dependency_3 " >> "$expected_file"
# --data=debug-versions
echo -n "-debug=someDebugVerIdent " >> "$expected_file"
echo -n "-debug=anotherDebugVerIdent " >> "$expected_file"
# --data=import-paths
echo -n "'-I$CURR_DIR/describe-project/src/' " >> "$expected_file"
echo -n "'-I$CURR_DIR/describe-dependency-1/source/' " >> "$expected_file"
echo -n "'-I$CURR_DIR/describe-dependency-2/some-path/' " >> "$expected_file"
echo -n "'-I$CURR_DIR/describe-dependency-3/dep3-source/' " >> "$expected_file"
# --data=string-import-paths
echo -n "'-J$CURR_DIR/describe-project/views/' " >> "$expected_file"
echo -n "'-J$CURR_DIR/describe-dependency-2/some-extra-string-import-path/' " >> "$expected_file"
echo -n "'-J$CURR_DIR/describe-dependency-3/dep3-string-import-path/' " >> "$expected_file"
# --data=import-files
echo -n "'$CURR_DIR/describe-dependency-2/some-path/dummy.d' " >> "$expected_file"
# --data=options
echo -n "-debug " >> "$expected_file"
# releaseMode is not included, even though it's specified, because the requireContracts requirement drops it
echo -n "-g " >> "$expected_file"
echo -n "-gx " >> "$expected_file"
echo -n "-wi" >> "$expected_file"
echo "" >> "$expected_file"

if ! diff "$expected_file" "$temp_file"; then
    die $LINENO 'The project data did not match the expected output!'
fi

