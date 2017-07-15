#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
packname="0-init-simple-pack"

$DUB init -n $packname -f json

function cleanup {
    rm -rf $packname
}

if [ ! -e $packname/dub.json ]; then
    cleanup
    die $LINENO 'No dub.json file has been generated.'
fi
cleanup
