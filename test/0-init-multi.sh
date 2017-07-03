#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
packname="0-init-multi-pack"
deps="openssl logger"
type="vibe.d"

$DUB init -n $packname $deps --type=$type --format sdl

function cleanup {
    rm -rf $packname
}

if [ ! -e $packname/dub.sdl ]; then # it failed, exit 1
    echo "No dub.sdl file has been generated."
    cleanup
    exit 1
else # check if resulting dub.sdl has all dependencies in tow
    deps="$deps vibe-d";
    IFS=" " read -a arr <<< "$deps"
    for ele in "${arr[@]}"
    do
        if [ `grep -c "$ele" $packname/dub.sdl` -ne 1 ]; then #something went wrong
            echo "$ele not in $packname/dub.sdl"
            cleanup
            exit 1
        fi
    done
    cleanup
    exit 0

fi
