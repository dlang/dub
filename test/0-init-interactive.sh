#!/bin/bash

packname="0-init-interactive"

echo -e "sdl\ntest\ndesc\nauthor\ngpl\ncopy\n\n" | $DUB init $packname

function cleanup {
    rm -rf $packname
}

if [ ! -e $packname/dub.sdl ]; then # it failed
    echo "No dub.sdl file has been generated."
    cleanup
    exit 1
fi

if ! diff $packname/dub.sdl "$CURR_DIR"/0-init-interactive.dub.sdl; then
	echo "Contents of generated dub.sdl not as expected."
	cleanup
	exit 1
fi

cleanup
exit 0
