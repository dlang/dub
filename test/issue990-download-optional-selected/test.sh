#!/bin/sh

rm -rf b/.dub
${DUB} remove gitcompatibledubpackage -n --version=*
${DUB} run || exit 1
