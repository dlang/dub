#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue923-subpackage-deps
rm -rf main/.dub
rm -rf a/.dub
rm -rf b/.dub
rm -f main/dub.selections.json
${DUB} build --bare --compiler=${DC} main


if ! grep -c -e \"b\" main/dub.selections.json; then
	die $LINENO 'Dependency b not resolved.'
fi
