#!/bin/sh

rm -rf a-1.0.0/.dub
rm -rf a-1.1.0/.dub
rm -rf main/.dub
${DUB} build --bare --compiler=${DC} main || exit 1
