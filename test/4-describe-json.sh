#!/bin/bash

set -e -o pipefail

cd "$CURR_DIR"/describe-project

temp_file=$(mktemp $(basename $0).XXXXXX)

function cleanup {
    rm $temp_file
}

trap cleanup EXIT

if ! $DUB describe --compiler=$DC > "$temp_file"; then
    die 'Printing describe JSON failed!'
fi

