#!/bin/sh

rm -rf .dub
if [ "${DC}" = "dmd" ]; then
	${DUB} build --compiler=${DC} || exit 1
else
	echo "Skipping shared library test for ${DC}..."
fi

