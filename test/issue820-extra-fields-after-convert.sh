#!/bin/sh

set -e

cd ${CURR_DIR}/1-exec-simple

cp dub.json dub.json.bak
${DUB} convert -f sdl

if grep -c -e "version\|sourcePaths\|importPaths\|configuration" dub.sdl > /dev/null; then
	echo "Conversion added extra fields."
	mv dub.json.bak dub.json
	rm dub.sdl
	exit 1
fi

mv dub.json.bak dub.json
rm dub.sdl
