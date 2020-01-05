#!/usr/bin/env bash

cd ${CURR_DIR}/issue1372-ignore-files-in-hidden-dirs/

echo "Compile and ignore hidden directories"
rm dub.json
ln -s dub_json_no_hidden.json dub.json
${DUB} build --force

rm dub.json

echo "Compile and explcitly include file in hidden directories"
ln -s dub_json_hidden.json dub.json
${DUB} build --force

rm dub.json
