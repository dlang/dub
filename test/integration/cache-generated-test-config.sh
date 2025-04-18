#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/cache-generated-test-config
rm -rf $HOME/.dub/cache/cache-generated-test-config/
DUB_CODE_CACHE_PATH="$HOME/.dub/cache/cache-generated-test-config/~master/code/"

## default test
${DUB} test --compiler=${DC}

STAT="stat -c '%Y'"
[[ "$OSTYPE" == "darwin"* ]] && STAT="stat -f '%m' -t '%Y'"

EXECUTABLE_TIME="$(${STAT} cache-generated-test-config-test-library)"
[ -z "$EXECUTABLE_TIME" ] && die $LINENO 'no EXECUTABLE_TIME was found'
MAIN_TIME="$(${STAT} "$(ls $DUB_CODE_CACHE_PATH/*/dub_test_root.d)")"
[ -z "$MAIN_TIME" ] && die $LINENO 'no MAIN_TIME was found'

${DUB} test --compiler=${DC}
MAIN_FILES_COUNT=$(ls $DUB_CODE_CACHE_PATH/*/dub_test_root.d | wc -l)

[ $MAIN_FILES_COUNT -ne 1 ] && die $LINENO 'DUB generated more then one main file'
[ "$EXECUTABLE_TIME" != "$(${STAT} cache-generated-test-config-test-library)" ] && die $LINENO 'The executable has been rebuilt'
[ "$MAIN_TIME" != "$(${STAT} "$(ls $DUB_CODE_CACHE_PATH/*/dub_test_root.d | head -n1)")" ] && die $LINENO 'The test main file has been rebuilt'

## test with empty DFLAGS environment variable
DFLAGS="" ${DUB} test --compiler=${DC}

STAT="stat -c '%Y'"
[[ "$OSTYPE" == "darwin"* ]] && STAT="stat -f '%m' -t '%Y'"

EXECUTABLE_TIME="$(${STAT} cache-generated-test-config-test-library)"
[ -z "$EXECUTABLE_TIME" ] && die $LINENO 'no EXECUTABLE_TIME was found'
MAIN_TIME="$(${STAT} "$(ls $DUB_CODE_CACHE_PATH/*-\$DFLAGS-*/dub_test_root.d)")"
[ -z "$MAIN_TIME" ] && die $LINENO 'no MAIN_TIME was found'

DFLAGS="" ${DUB} test --compiler=${DC}
MAIN_FILES_COUNT=$(ls $DUB_CODE_CACHE_PATH/*-\$DFLAGS-*/dub_test_root.d | wc -l)

[ $MAIN_FILES_COUNT -ne 1 ] && die $LINENO 'DUB generated more then one main file'
[ "$EXECUTABLE_TIME" != "$(${STAT} cache-generated-test-config-test-library)" ] && die $LINENO 'The executable has been rebuilt'
[ "$MAIN_TIME" != "$(${STAT} "$(ls $DUB_CODE_CACHE_PATH/*-\$DFLAGS-*/dub_test_root.d | head -n1)")" ] && die $LINENO 'The test main file has been rebuilt'

## test with DFLAGS environment variable
DFLAGS="-g" ${DUB} test --compiler=${DC}

STAT="stat -c '%Y'"
[[ "$OSTYPE" == "darwin"* ]] && STAT="stat -f '%m' -t '%Y'"

EXECUTABLE_TIME="$(${STAT} cache-generated-test-config-test-library)"
[ -z "$EXECUTABLE_TIME" ] && die $LINENO 'no EXECUTABLE_TIME was found'
MAIN_TIME="$(${STAT} "$(ls $DUB_CODE_CACHE_PATH/*-\$DFLAGS-*/dub_test_root.d)")"
[ -z "$MAIN_TIME" ] && die $LINENO 'no MAIN_TIME was found'

DFLAGS="-g" ${DUB} test --compiler=${DC}
MAIN_FILES_COUNT=$(ls $DUB_CODE_CACHE_PATH/*-\$DFLAGS-*/dub_test_root.d | wc -l)

[ $MAIN_FILES_COUNT -ne 1 ] && die $LINENO 'DUB generated more then one main file'
[ "$EXECUTABLE_TIME" != "$(${STAT} cache-generated-test-config-test-library)" ] && die $LINENO 'The executable has been rebuilt'
[ "$MAIN_TIME" != "$(${STAT} "$(ls $DUB_CODE_CACHE_PATH/*-\$DFLAGS-*/dub_test_root.d | head -n1)")" ] && die $LINENO 'The test main file has been rebuilt'



exit 0
