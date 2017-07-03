#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
packname="0-init-simple-pack"

$DUB init -n $packname --format sdl

function cleanup {
    rm -rf $packname
}

if [ ! -e $packname/dub.sdl ]; then # it failed
    echo "No dub.sdl file has been generated."
    cleanup
    exit 1
fi
cleanup
exit 0
