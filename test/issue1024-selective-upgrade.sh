#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue1024-selective-upgrade
echo "{\"fileVersion\": 1,\"versions\": {\"a\": \"1.0.0\", \"b\": \"1.0.0\"}}" > main/dub.selections.json
$DUB upgrade --bare --root=main a

if ! grep -c -e "\"a\": \"1.0.1\"" main/dub.selections.json; then
	die $LINENO "Specified dependency was not upgraded."
fi

if grep -c -e "\"b\": \"1.0.1\"" main/dub.selections.json; then
	die $LINENO "Non-specified dependency got upgraded."
fi
