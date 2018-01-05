#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
packname="0-init-fail-pack"
deps="logger PACKAGE_DONT_EXIST" # would be very unlucky if it does exist...

if $DUB init -n $packname $deps 2>/dev/null; then
    die $LINENO 'Init with unknown non-existing dependency expected to fail'
fi

function cleanup {
    rm -rf $packname
}

if [ -e $packname/dub.sdl ]; then # package is there, it should have failed
    cleanup
    die $LINENO "$packname/dub.sdl was not created"
fi
