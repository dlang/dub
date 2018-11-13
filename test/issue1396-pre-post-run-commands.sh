#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue1396-pre-post-run-commands
rm -rf .dub
rm -rf test.txt
"$DUB"

if ! grep -c -e "pre-run" test.txt; then
	die $LINENO 'pre run not executed.'
fi

if ! grep -c -e "post-run-0" test.txt; then
	die $LINENO 'post run not executed.'
fi
