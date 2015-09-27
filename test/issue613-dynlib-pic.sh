#!/bin/sh

cd ${CURR_DIR}/issue613-dynlib-pic
rm -rf .dub
if [ "${DC}" = "dmd" ]; then
	${DUB} build --compiler=${DC} || exit 1
else
	echo "Skipping shared library test for ${DC}..."
fi

