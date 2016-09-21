#!/bin/sh

set -e

cd ${CURR_DIR}/1-exec-simple

EXPECTED="name \"exec-simple\"
targetType \"executable\""

RESULT=`${DUB} convert -s -f sdl`

if [ ! -f dub.json ]; then
	echo "Package recipe got modified!"
	exit 1
fi

if [ -f dub.sdl ]; then
	echo "An SDL recipe got written."
	exit 2
fi

if [ "$RESULT" != "$EXPECTED" ]; then
	echo "Unexpected SDLang output."
	exit 3
fi
