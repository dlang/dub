#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd ${CURR_DIR}/1-exec-simple

EXPECTED="name \"exec-simple\"
targetType \"executable\""

RESULT=`${DUB} convert -s -f sdl`

if [ ! -f dub.json ]; then
	die $LINENO 'Package recipe got modified!'
fi

if [ -f dub.sdl ]; then
	die $LINENO 'An SDL recipe got written.'
fi

if [ "$RESULT" != "$EXPECTED" ]; then
	die $LINENO 'Unexpected SDLang output.'
fi
