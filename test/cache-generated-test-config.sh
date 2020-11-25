#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/cache-generated-test-config
rm -rf .dub

${DUB} test --compiler=${DC}

STAT="stat -c '%Y'"
[[ "$OSTYPE" == "darwin"* ]] && STAT="stat -f '%m' -t '%Y'"

EXECUTABLE_TIME="$(${STAT} cache-generated-test-config-test-library)"
[ -z "$EXECUTABLE_TIME" ] && die $LINENO 'no EXECUTABLE_TIME was found'
MAIN_TIME="$(${STAT} "$(ls .dub/code/*dub_test_root.d)")"
[ -z "$MAIN_TIME" ] && die $LINENO 'no MAIN_TIME was found'

${DUB} test --compiler=${DC}
MAIN_FILES_COUNT=$(ls .dub/code/*dub_test_root.d | wc -l)

[ $MAIN_FILES_COUNT -ne 1 ] && die $LINENO 'DUB generated more then one main file'
[ "$EXECUTABLE_TIME" != "$(${STAT} cache-generated-test-config-test-library)" ] && die $LINENO 'The executable has been rebuilt'
[ "$MAIN_TIME" != "$(${STAT} "$(ls .dub/code/*dub_test_root.d | head -n1)")" ] && die $LINENO 'The test main file has been rebuilt'

exit 0