#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

postfix=$RANDOM
HOME_STRING="issue1099_HOME_TEMP_${postfix}"

mkdir $HOME_STRING
export HOME=$(pwd)/$HOME_STRING


function cleanup {
    cd ../
    rm -rf $HOME
}

trap cleanup EXIT

mkdir $HOME/.dub/
touch $HOME/.dub/settings.json

cd ${CURR_DIR}/issue1099-empty-settings-json

if ! ${DUB} build --force ; then
    die "Dub failed to build with an empty settings.json"
fi
