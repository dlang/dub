#!/usr/bin/env bash

if ! command -v dustmite &> /dev/null
then
    echo "Skipping test because dustmite is not installed!"
    exit 0
fi

. $(dirname "${BASH_SOURCE[0]}")/common.sh

DM_TEST="$CURR_DIR/dustmite-no-redirect-test/project"
DM_TMP="$DM_TEST-dusting"
EXPECTED="This text should be shown!"
LOG="$DM_TEST.log"

rm -rf $DM_TMP $DM_TMP.*

$DUB --root=$DM_TEST dustmite --no-redirect --program-status=1 $DM_TMP &> $LOG || true

if ! grep -q "$EXPECTED" "$LOG"
then
    cat $LOG
    die $LINENO "Diff between expected and actual output"
fi

rm -rf $DM_TMP $DM_TMP.* $LOG
