#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd ${CURR_DIR}/issue1158-stdin-for-single-files

if ! { cat stdin.d | ${DUB} - --value=v 2>&1 || true; } | grep -cF '["--value=v"]'; then
	die $LINENO 'Stdin for single files failed.'
fi