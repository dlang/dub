#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

mkdir issue1099_HOME_TEMP

export HOME=$(pwd)/issue1099_HOME_TEMP

function cleanup {
    cd ../
    rm -rf issue1099_HOME_TEMP
}

trap cleanup EXIT

mkdir $HOME/.dub/
touch $HOME/.dub/settings.json

cd ${CURR_DIR}/issue1099-empty-settings-json

if ! ${DUB} build --force ; then
    die "Dub failed to build with an empty settings.json"
fi
