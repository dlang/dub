#!/bin/sh

cd ${CURR_DIR}/issue990-download-optional-selected
rm -rf b/.dub
${DUB} remove gitcompatibledubpackage -n --version=*
${DUB} run || exit 1
