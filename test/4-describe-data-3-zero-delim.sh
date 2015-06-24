#!/bin/bash

set -e -o pipefail

cd "$CURR_DIR"/describe-project

temp_file_normal=`mktemp`
temp_file_zero_delim=`mktemp`

function cleanup {
    rm $temp_file_normal
    rm $temp_file_zero_delim
}

trap cleanup EXIT

# Test list-style project data
if ! $DUB describe --compiler=$COMPILER --data-list \
    --data=target-type \
    --data=target-path \
    --data=target-name \
    --data=working-directory \
    --data=main-source-file \
    --data=dflags \
    --data=lflags \
    --data=libs \
    --data=linker-files \
    --data=source-files \
    --data=copy-files \
    --data=versions \
    --data=debug-versions \
    --data=import-paths \
    --data=string-import-paths \
    --data=import-files \
    --data=string-import-files \
    --data=pre-generate-commands \
    --data=post-generate-commands \
    --data=pre-build-commands \
    --data=post-build-commands \
    --data=requirements \
    --data=options \
    > "$temp_file_normal"; then
    die 'Printing list-style project data failed!'
fi

if ! $DUB describe --compiler=$COMPILER --data-0 --data-list \
    --data=target-type \
    --data=target-path \
    --data=target-name \
    --data=working-directory \
    --data=main-source-file \
    --data=dflags \
    --data=lflags \
    --data=libs \
    --data=linker-files \
    --data=source-files \
    --data=copy-files \
    --data=versions \
    --data=debug-versions \
    --data=import-paths \
    --data=string-import-paths \
    --data=import-files \
    --data=string-import-files \
    --data=pre-generate-commands \
    --data=post-generate-commands \
    --data=pre-build-commands \
    --data=post-build-commands \
    --data=requirements \
    --data=options \
    | xargs -0 printf "%s\n" > "$temp_file_zero_delim"; then
    die 'Printing null-delimited list-style project data failed!'
fi

if ! diff -Z "$temp_file_normal" "$temp_file_zero_delim"; then
    die 'The null-delimited list-style project data did not match the expected output!'
fi

# Test --import-paths
if ! $DUB describe --compiler=$COMPILER --import-paths \
    > "$temp_file_normal"; then
    die 'Printing --import-paths failed!'
fi

if ! $DUB describe --compiler=$COMPILER --data-0 --import-paths \
    | xargs -0 printf "%s\n" > "$temp_file_zero_delim"; then
    die 'Printing null-delimited --import-paths failed!'
fi

if ! diff -Z -B "$temp_file_normal" "$temp_file_zero_delim"; then
    die 'The null-delimited --import-paths data did not match the expected output!'
fi

# DMD-only beyond this point
if ! dmd --help >/dev/null; then
	echo Skipping DMD-centric tests on configuration that lacks DMD.
	exit
fi

# Test dmd-style --data=versions
if ! $DUB describe --compiler=dmd --data=versions \
    > "$temp_file_normal"; then
    die 'Printing dmd-style --data=versions failed!'
fi

if ! $DUB describe --compiler=dmd --data-0 --data=versions \
    | xargs -0 printf "%s " > "$temp_file_zero_delim"; then
    die 'Printing null-delimited dmd-style --data=versions failed!'
fi

if ! diff -Z "$temp_file_normal" "$temp_file_zero_delim"; then
    die 'The null-delimited dmd-style --data=versions did not match the expected output!'
fi

# Test dmd-style --data=source-files
if ! $DUB describe --compiler=dmd --data=source-files \
    > "$temp_file_normal"; then
    die 'Printing dmd-style --data=source-files failed!'
fi

if ! $DUB describe --compiler=dmd --data-0 --data=source-files \
    | xargs -0 printf "'%s' " > "$temp_file_zero_delim"; then
    die 'Printing null-delimited dmd-style --data=source-files failed!'
fi

if ! diff -Z "$temp_file_normal" "$temp_file_zero_delim"; then
    die 'The null-delimited dmd-style --data=source-files did not match the expected output!'
fi
