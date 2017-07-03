#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue1024-selective-upgrade
echo "{\"fileVersion\": 1,\"versions\": {\"a\": \"1.0.0\", \"b\": \"1.0.0\"}}" > main/dub.selections.json
$DUB upgrade --bare --root=main a || exit 1

if ! grep -c -e "\"a\": \"1.0.1\"" main/dub.selections.json; then
	echo "Specified dependency was not upgraded."
	exit 1
fi

if grep -c -e "\"b\": \"1.0.1\"" main/dub.selections.json; then
	echo "Non-specified dependency got upgraded."
	exit 1
fi
