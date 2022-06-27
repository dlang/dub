#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

rm -f 1-staticLib-simple/dub.selections.json

if ! ${DUB} test --root 1-staticLib-simple; then
    die $LINENO 'The test command failed.'
fi

if [ -f "1-staticLib-simple/dub.selections.json" ]; then
    die $LINENO 'The test command has unexpectedly generated a dub.selections.json file.'
fi
