#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd "$CURR_DIR"/5-convert

temp_file=$(mktemp $(basename $0).XXXXXX)

function cleanup {
    rm $temp_file
}
trap cleanup EXIT

cp dub.sdl dub.sdl.ref

$DUB convert -f json

if [ -f "dub.sdl" ]; then die $LINENO 'Old recipe file not removed.'; fi
if [ ! -f "dub.json" ]; then die $LINENO 'New recipe file not created.'; fi

$DUB convert -f sdl

if [ -f "dub.json" ]; then die $LINENO 'Old recipe file not removed.'; fi
if [ ! -f "dub.sdl" ]; then die $LINENO 'New recipe file not created.'; fi

if ! diff "dub.sdl" "dub.sdl.ref"; then
    die $LINENO 'The project data did not match the expected output!'
fi

rm dub.sdl.ref

