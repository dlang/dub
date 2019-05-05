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

if ! { ${DUB} build --force 2>&1 || true; } | grep -cF 'settings.json(1): Error: JSON string is empty.' ; then
    die "Should have thrown with the message: '/settings.json(1): Error: JSON string is empty', but we threw something else"
fi
