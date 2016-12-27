#!/bin/sh

rm -rf main/.dub
rm -rf sub/.dub
rm -rf sub/sub/.dub
${DUB} build --bare --compiler=${DC} main || exit 1
