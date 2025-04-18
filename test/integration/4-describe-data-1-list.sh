#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd "$CURR_DIR"/describe-project

temp_file=$(mktemp $(basename $0).XXXXXX)

function cleanup {
    rm $temp_file
}

trap cleanup EXIT

if ! $DUB describe --compiler=$DC --filter-versions \
     --data-list \
    '--data= target-type , target-path , target-name ' \
    '--data= working-directory ' \
    --data=main-source-file \
    '--data=dflags,lflags' \
    '--data=libs, linker-files' \
    '--data=source-files, copy-files' \
    '--data=versions, debug-versions' \
    --data=import-paths \
    --data=string-import-paths \
    --data=import-files \
    --data=string-import-files \
    --data=pre-generate-commands \
    --data=post-generate-commands \
    --data=pre-build-commands \
    --data=post-build-commands \
    '--data=requirements, options' \
    --data=default-config \
    --data=configs \
    --data=default-build \
    --data=builds \
    > "$temp_file"; then
    die $LINENO 'Printing project data failed!'
fi

# Create the expected output path file to compare against.
expected_file="$CURR_DIR/expected-describe-data-1-list-output"
# --data=target-type
echo "executable" > "$expected_file"
echo >> "$expected_file"
# --data=target-path
echo "$CURR_DIR/describe-project/" >> "$expected_file"
echo >> "$expected_file"
# --data=target-name
echo "describe-project" >> "$expected_file"
echo >> "$expected_file"
# --data=working-directory
echo "$CURR_DIR/describe-project/" >> "$expected_file"
echo >> "$expected_file"
# --data=main-source-file
echo "$CURR_DIR/describe-project/src/dummy.d" >> "$expected_file"
echo >> "$expected_file"
# --data=dflags
echo "--some-dflag" >> "$expected_file"
echo "--another-dflag" >> "$expected_file"
echo >> "$expected_file"
# --data=lflags
echo "--some-lflag" >> "$expected_file"
echo "--another-lflag" >> "$expected_file"
echo >> "$expected_file"
# --data=libs
echo "somelib" >> "$expected_file"
echo "anotherlib" >> "$expected_file"
echo >> "$expected_file"
# --data=linker-files
echo "$CURR_DIR/describe-dependency-3/libdescribe-dependency-3.a" >> "$expected_file"
echo "$CURR_DIR/describe-project/some.a" >> "$expected_file"
echo "$CURR_DIR/describe-dependency-1/dep.a" >> "$expected_file"
echo >> "$expected_file"
# --data=source-files
echo "$CURR_DIR/describe-project/src/dummy.d" >> "$expected_file"
echo "$CURR_DIR/describe-dependency-1/source/dummy.d" >> "$expected_file"
echo >> "$expected_file"
# --data=copy-files
echo "$CURR_DIR/describe-project/data/dummy.dat" >> "$expected_file"
echo "$CURR_DIR/describe-dependency-1/data/*" >> "$expected_file"
echo >> "$expected_file"
# --data=versions
echo "someVerIdent" >> "$expected_file"
echo "anotherVerIdent" >> "$expected_file"
echo "Have_describe_dependency_3" >> "$expected_file"
echo >> "$expected_file"
# --data=debug-versions
echo "someDebugVerIdent" >> "$expected_file"
echo "anotherDebugVerIdent" >> "$expected_file"
echo >> "$expected_file"
# --data=import-paths
echo "$CURR_DIR/describe-project/src/" >> "$expected_file"
echo "$CURR_DIR/describe-dependency-1/source/" >> "$expected_file"
echo "$CURR_DIR/describe-dependency-2/some-path/" >> "$expected_file"
echo "$CURR_DIR/describe-dependency-3/dep3-source/" >> "$expected_file"
echo >> "$expected_file"
# --data=string-import-paths
echo "$CURR_DIR/describe-project/views/" >> "$expected_file"
echo "$CURR_DIR/describe-dependency-2/some-extra-string-import-path/" >> "$expected_file"
echo "$CURR_DIR/describe-dependency-3/dep3-string-import-path/" >> "$expected_file"
echo >> "$expected_file"
# --data=import-files
echo "$CURR_DIR/describe-dependency-2/some-path/dummy.d" >> "$expected_file"
echo >> "$expected_file"
# --data=string-import-files
echo "$CURR_DIR/describe-project/views/dummy.d" >> "$expected_file"
#echo "$CURR_DIR/describe-dependency-2/some-extra-string-import-path/dummy.d" >> "$expected_file" # This is missing from result, is that a bug?
echo >> "$expected_file"
# --data=pre-generate-commands
echo "./do-preGenerateCommands.sh" >> "$expected_file"
echo "../describe-dependency-1/dependency-preGenerateCommands.sh" >> "$expected_file"
echo >> "$expected_file"
# --data=post-generate-commands
echo "./do-postGenerateCommands.sh" >> "$expected_file"
echo "../describe-dependency-1/dependency-postGenerateCommands.sh" >> "$expected_file"
echo >> "$expected_file"
# --data=pre-build-commands
echo "./do-preBuildCommands.sh" >> "$expected_file"
echo "../describe-dependency-1/dependency-preBuildCommands.sh" >> "$expected_file"
echo >> "$expected_file"
# --data=post-build-commands
echo "./do-postBuildCommands.sh" >> "$expected_file"
echo "../describe-dependency-1/dependency-postBuildCommands.sh" >> "$expected_file"
echo >> "$expected_file"
# --data=requirements
echo "allowWarnings" >> "$expected_file"
echo "disallowInlining" >> "$expected_file"
echo "requireContracts" >> "$expected_file"
echo >> "$expected_file"
# --data=options
echo "debugMode" >> "$expected_file"
# releaseMode is not included, even though it's specified, because the requireContracts requirement drops it
echo "debugInfo" >> "$expected_file"
echo "stackStomping" >> "$expected_file"
echo "warnings" >> "$expected_file"
echo >> "$expected_file"
# --data=default-config
echo "my-project-config" >> "$expected_file"
echo >> "$expected_file"
# --data=configs
echo "my-project-config" >> "$expected_file"
echo >> "$expected_file"
# --data=default-build
echo "debug" >> "$expected_file"
echo >> "$expected_file"
# --data=builds
echo "debug" >> "$expected_file"
echo "plain" >> "$expected_file"
echo "release" >> "$expected_file"
echo "release-debug" >> "$expected_file"
echo "release-nobounds" >> "$expected_file"
echo "unittest" >> "$expected_file"
echo "profile" >> "$expected_file"
echo "profile-gc" >> "$expected_file"
echo "docs" >> "$expected_file"
echo "ddox" >> "$expected_file"
echo "cov" >> "$expected_file"
echo "cov-ctfe" >> "$expected_file"
echo "unittest-cov" >> "$expected_file"
echo "unittest-cov-ctfe" >> "$expected_file"
echo "syntax" >> "$expected_file"
# echo >> "$expected_file"

if ! diff "$expected_file" "$temp_file"; then
    echo "Result:"
    cat "$temp_file"
    die $LINENO 'The project data did not match the expected output!'
fi

