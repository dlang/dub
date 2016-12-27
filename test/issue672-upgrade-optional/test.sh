#!/bin/sh

rm -rf b/.dub
echo "{\"fileVersion\": 1,\"versions\": {\"dub\": \"1.0.0\"}}" > dub.selections.json
${DUB} upgrade || exit 1

if ! grep -c -e "\"dub\": \"1.1.0\"" dub.selections.json; then
	echo "Dependency not upgraded."
	exit 1
fi
