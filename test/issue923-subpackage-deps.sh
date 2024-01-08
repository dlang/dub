#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue923-subpackage-deps
rm -f main/~master/main/dub.selections.json
${DUB} build -f --bare --compiler=${DC} main


if ! grep -c -e \"b\" main/~master/main/dub.selections.json; then
	die $LINENO 'Dependency b not resolved.'
fi
