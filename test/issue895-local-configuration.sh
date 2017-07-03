#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd ${CURR_DIR}
mkdir ../etc
mkdir ../etc/dub
echo "{\"defaultCompiler\": \"foo\"}" > ../etc/dub/settings.json

if [ -e /var/lib/dub/settings.json ]; then
	echo "Found existing system wide DUB configuration. Aborting."
	exit 1
fi

if [ -e ~/.dub/settings.json ]; then
	echo "Found existing user wide DUB configuration. Aborting."
	exit 1
fi

if ! ${DUB} describe --single issue103-single-file-package.d 2>&1 | grep -e "Unknown compiler: foo" -c > /dev/null; then
	rm -r ../etc
	echo "DUB didn't find the local configuration"
	exit 1
fi

rm -r ../etc
