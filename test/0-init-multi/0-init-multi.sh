#!/bin/bash

packname="0-init-multi-pack"
deps="openssl logger"
type="vibe.d"

$DUB init $packname $deps --type=$type

function cleanup {
    rm -rf $packname
}

if [ ! -e $packname/dub.json ]; then # it failed, exit 1
    exit 1
else # check if resulting dub.json has all dependancies in tow
    deps="$deps vibe-d";
    IFS=" " read -a arr <<< "$deps"
    for ele in "${arr[@]}"
    do
        if [ `grep -c "$ele" $packname/dub.json` -ne 1 ]; then #something went wrong
            echo "$ele not in $packname/dub.json"
            cleanup
            exit 1
        fi
    done
    cleanup
    exit 0

fi
