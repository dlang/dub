#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd ${CURR_DIR}
mkdir ../etc
mkdir ../etc/dub
echo "{\"defaultCompiler\": \"foo\"}" > ../etc/dub/settings.json

if [ -e /var/lib/dub/settings.json ]; then
	die $LINENO 'Found existing system wide DUB configuration. Aborting.'
fi

if [ -e ~/.dub/settings.json ]; then
	die $LINENO 'Found existing user wide DUB configuration. Aborting.'
fi

if ! { ${DUB} describe --single issue103-single-file-package.d 2>&1 || true; } | grep -cF 'Unknown compiler: foo'; then
	rm -r ../etc
	die $LINENO 'DUB did not find the local configuration'
fi

rm -r ../etc
