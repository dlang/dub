#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
packname="0-init-interactive"

echo -e "sdl\ntest\ndesc\nauthor\ngpl\ncopy\n\n" | $DUB init $packname

function cleanup {
    rm -rf $packname
}

if [ ! -e $packname/dub.sdl ]; then # it failed
    cleanup
    die $LINENO 'No dub.sdl file has been generated.'
fi

if ! diff $packname/dub.sdl "$CURR_DIR"/0-init-interactive.dub.sdl; then
    cleanup
    die $LINENO 'Contents of generated dub.sdl not as expected.'
fi

cleanup
