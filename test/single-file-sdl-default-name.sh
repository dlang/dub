#!/bin/sh
set -e
cd ${CURR_DIR}
rm -f single-file-sdl-default-name

${DUB} run --single single-file-sdl-default-name.d --compiler=${DC}
if [ ! -f single-file-sdl-default-name ]; then
	echo "Normal invocation did not produce a binary in the current directory"
	exit 1
fi
rm single-file-sdl-default-name
