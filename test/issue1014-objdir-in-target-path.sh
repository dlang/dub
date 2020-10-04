#!/bin/sh

set -e
cd ${CURR_DIR}/issue1014

# Test 1. Single compilation
${DUB} build --single --compiler=${DC} issue1014.d

if test -d ".dub/obj"; then
    echo "junk directory created when running ldc"
    find .dub/obj
    exit 1
fi
rm -rf .dub

# Test 2. Shebang, expecting no .dub in the current directory
export PATH=$(dirname ${DUB}):$PATH
chmod 755 issue1014.d
./issue1014.d

if test -d ".dub"; then
    echo "junk directory created when running shebang with ldc"
    find .dub
    exit 1
fi

cd ${CURR_DIR}
