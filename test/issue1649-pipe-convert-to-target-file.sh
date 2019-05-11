#!/usr/bin/env bash

cd ${CURR_DIR}/issue1649-pipe-convert-to-target-file

# https://github.com/dlang/dub/issues/1649
# Case: dub convert prints the new file to stdout.
# We want to write it into a target file using pipes.
$DUB convert -s -f json > dub.json

function cleanup {
    rm dub.json
}

if [ ! -s dub.json ]; then
    cleanup
    die $LINENO 'dub.json was not written to.'
fi
cleanup