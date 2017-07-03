#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue613-dynlib-pic
rm -rf .dub
if [ "${DC}" = "dmd" ]; then
	${DUB} build --compiler=${DC}
else
	echo "Skipping shared library test for ${DC}..."
fi
