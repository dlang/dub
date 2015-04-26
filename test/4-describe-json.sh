#!/bin/bash

cd "$CURR_DIR"/describe-project

$DUB describe --compiler=$COMPILER > /dev/null

if (( $? )); then
    die 'Printing describe JSON failed!'
fi

exit 0
