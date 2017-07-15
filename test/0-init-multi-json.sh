#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
packname="0-init-multi-pack"
deps="openssl logger"
type="vibe.d"

$DUB init -n $packname $deps --type=$type -f json

function cleanup {
    rm -rf $packname
}

if [ ! -e $packname/dub.json ]; then
    die $LINENO '$packname/dub.json not created'
else # check if resulting dub.json has all dependencies in tow
    deps="$deps vibe-d";
    IFS=" " read -a arr <<< "$deps"
    for ele in "${arr[@]}"
    do
        if [ `grep -c "$ele" $packname/dub.json` -ne 1 ]; then #something went wrong
            cleanup
            die $LINENO "$ele not in $packname/dub.json"
        fi
    done
    cleanup
fi
