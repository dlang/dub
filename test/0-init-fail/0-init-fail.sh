#!/bin/bash

packname="0-init-fail-pack"
deps="logger PACKAGE_DONT_EXIST" # would be very unlucky if it does exist...

$DUB init $packname $deps

function cleanup {
    rm -rf $packname
}

if [ -e $packname/dub.json ]; then # package is there, it should have failed
    cleanup
    exit 1
fi
exit 0
