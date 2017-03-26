#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
packname="0-init-interactive"

function cleanup {
    rm -rf $packname
}

function runTest {
    local inp=$1
    local comp=$2
    local dub_ext=${comp##*.}
    echo -e $inp | $DUB init $packname &>/dev/null
    if [ ! -e $packname/dub.$dub_ext ]; then # it failed
        cleanup
        die $LINENO "No dub.$dub_ext file has been generated for test $comp."
    fi
    if ! diff $packname/dub.$dub_ext "$CURR_DIR"/$comp; then
	cleanup
	die $LINENO "Contents of generated dub.$dub_ext not as expected."
    fi
    cleanup
}

# sdl package format
runTest '0\ntest\ndesc\nauthor\ngpl\ncopy\n\n' 0-init-interactive.dub.sdl
# select package format out of bounds
runTest '3\n0\ntest\ndesc\nauthor\ngpl\ncopy\n\n' 0-init-interactive.dub.sdl
# select package format not numeric
runTest 'sdl\n0\ntest\ndesc\nauthor\ngpl\ncopy\n\n' 0-init-interactive.dub.sdl
# default name
runTest '0\n\ndesc\nauthor\ngpl\ncopy\n\n' 0-init-interactive.default_name.dub.sdl
# json package format
runTest '1\ntest\ndesc\nauthor\ngpl\ncopy\n\n' 0-init-interactive.dub.json
# default package format
runTest '\ntest\ndesc\nauthor\ngpl\ncopy\n\n' 0-init-interactive.dub.json
# select license
runTest '0\ntest\ndesc\nauthor\n3\ncopy\n\n' 0-init-interactive.license_gpl3.dub.sdl
# select license out of bounds
runTest '0\ntest\ndesc\nauthor\n21\n3\ncopy\n\n' 0-init-interactive.license_gpl3.dub.sdl
# default license
runTest '0\ntest\ndesc\nauthor\n\ncopy\n\n' 0-init-interactive.license_proprietary.dub.sdl
