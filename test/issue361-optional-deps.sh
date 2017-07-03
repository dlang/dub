#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue361-optional-deps
rm -rf a/.dub
rm -rf a/b/.dub
rm -rf main1/.dub
rm -rf main2/.dub
rm -f main1/dub.selections.json

${DUB} build --bare --compiler=${DC} main1 || exit 1
echo "{" > cmp.tmp
echo "	\"fileVersion\": 1," >> cmp.tmp
echo "	\"versions\": {" >> cmp.tmp
echo "		\"b\": \"~master\"" >> cmp.tmp
echo "	}" >> cmp.tmp
echo "}" >> cmp.tmp
diff cmp.tmp main1/dub.selections.json || exit 1

${DUB} build --bare --compiler=${DC} main2 || exit 1
echo "{" > cmp.tmp
echo "	\"fileVersion\": 1," >> cmp.tmp
echo "	\"versions\": {" >> cmp.tmp
echo "		\"a\": \"~master\"" >> cmp.tmp
echo "	}" >> cmp.tmp
echo "}" >> cmp.tmp
diff cmp.tmp main2/dub.selections.json || exit 1
