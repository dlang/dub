#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd ${CURR_DIR}/1-exec-simple

cp dub.json dub.json.bak
${DUB} convert -f sdl

if grep -qe "version\|sourcePaths\|importPaths\|configuration" dub.sdl > /dev/null; then
	mv dub.json.bak dub.json
	rm dub.sdl
	die $LINENO 'Conversion added extra fields.'
fi

mv dub.json.bak dub.json
rm dub.sdl
