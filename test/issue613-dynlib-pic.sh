#!/bin/sh

cd ${CURR_DIR}/issue613-dynlib-pic
rm -rf .dub
if [ "${COMPILER}" = "dmd" ]; then
	${DUB} build --compiler=${COMPILER} || exit 1
else
	echo "Skipping shared library test for ${COMPILER}..."
fi

