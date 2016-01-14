#!/bin/bash

packname="0-init-simple-pack"

$DUB init -n $packname -f json

function cleanup {
    rm -rf $packname
}

if [ ! -e $packname/dub.json ]; then # it failed
    cleanup
    exit 1
fi
cleanup
exit 0
