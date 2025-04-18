#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd "$CURR_DIR"/describe-project

temp_file_normal=$(mktemp $(basename $0).XXXXXX)
temp_file_zero_delim=$(mktemp $(basename $0).XXXXXX)

function cleanup {
    rm $temp_file_normal
    rm $temp_file_zero_delim
}

trap cleanup EXIT

# Test list-style project data
if ! $DUB describe --compiler=$DC --data-list \
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
    die $LINENO 'Printing list-style project data failed!'
fi

if ! $DUB describe --compiler=$DC --data-0 --data-list \
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
    die $LINENO 'Printing null-delimited list-style project data failed!'
fi

if ! diff -b -B "$temp_file_normal" "$temp_file_zero_delim"; then
    die $LINENO 'The null-delimited list-style project data did not match the expected output!'
fi

# Test --import-paths
if ! $DUB describe --compiler=$DC --import-paths \
    > "$temp_file_normal"; then
    die $LINENO 'Printing --import-paths failed!'
fi

if ! $DUB describe --compiler=$DC --data-0 --import-paths \
    | xargs -0 printf "%s\n" > "$temp_file_zero_delim"; then
    die $LINENO 'Printing null-delimited --import-paths failed!'
fi

if ! diff -b -B "$temp_file_normal" "$temp_file_zero_delim"; then
    die $LINENO 'The null-delimited --import-paths data did not match the expected output!'
fi

# DMD-only beyond this point
if [ "${DC}" != "dmd" ]; then
    echo Skipping DMD-centric tests on configuration that lacks DMD.
    exit
fi

# Test dmd-style --data=versions
if ! $DUB describe --compiler=$DC --data=versions \
    > "$temp_file_normal"; then
    die $LINENO 'Printing dmd-style --data=versions failed!'
fi

if ! $DUB describe --compiler=$DC --data-0 --data=versions \
    | xargs -0 printf "%s " > "$temp_file_zero_delim"; then
    die $LINENO 'Printing null-delimited dmd-style --data=versions failed!'
fi

if ! diff -b -B "$temp_file_normal" "$temp_file_zero_delim"; then
    die $LINENO 'The null-delimited dmd-style --data=versions did not match the expected output!'
fi

# check if escaping is required
. "$CURR_DIR/4-describe-data-check-escape"

# Test dmd-style --data=source-files
if ! $DUB describe --compiler=$DC --data=source-files \
    > "$temp_file_normal"; then
    die $LINENO 'Printing dmd-style --data=source-files failed!'
fi

if ! $DUB describe --compiler=$DC --data-0 --data=source-files \
    | xargs -0 printf "$(escaped "%s") " > "$temp_file_zero_delim"; then
    die $LINENO 'Printing null-delimited dmd-style --data=source-files failed!'
fi

if ! diff -b -B "$temp_file_normal" "$temp_file_zero_delim"; then
    die $LINENO 'The null-delimited dmd-style --data=source-files did not match the expected output!'
fi
