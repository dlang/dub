#!/bin/bash

set -e -o pipefail

cd "$CURR_DIR"/5-convert

temp_file=$(mktemp $(basename $0).XXXXXX)

function cleanup {
    rm $temp_file
}

function die {
	echo "$@" 1>&2
	exit 1
}

trap cleanup EXIT

cp dub.sdl dub.sdl.ref

$DUB convert -f json

if [ -f "dub.sdl" ]; then die 'Old recipe file not removed.'; fi
if [ ! -f "dub.json" ]; then die 'New recipe file not created.'; fi

$DUB convert -f sdl

if [ -f "dub.json" ]; then die 'Old recipe file not removed.'; fi
if [ ! -f "dub.sdl" ]; then die 'New recipe file not created.'; fi

if ! diff "dub.sdl" "dub.sdl.ref"; then
    die 'The project data did not match the expected output!'
fi

rm dub.sdl.ref

echo OK

