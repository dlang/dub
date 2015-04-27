#!/bin/bash

set -e -o pipefail

cd "$CURR_DIR"/describe-project

temp_file=`mktemp`

function cleanup {
    rm $temp_file
}

trap cleanup EXIT

if ! $DUB describe --compiler=$COMPILER > "$temp_file"; then
    die 'Printing describe JSON failed!'
fi

