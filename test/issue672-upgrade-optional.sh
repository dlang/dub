#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue672-upgrade-optional
rm -rf b/.dub
echo "{\"fileVersion\": 1,\"versions\": {\"dub\": \"1.5.0\"}}" > dub.selections.json
${DUB} upgrade

if ! grep -c -e "\"dub\": \"1.6.0\"" dub.selections.json; then
	die $LINENO 'Dependency not upgraded.'
fi
