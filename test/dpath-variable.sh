#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
export DPATH="${CURR_DIR}/dpath-variable/dpath"
rm -rf "$DPATH"
cd ${CURR_DIR}/dpath-variable
${DUB} upgrade

if [[ ! -f "$DPATH/dub/packages/gitcompatibledubpackage-1.0.1/gitcompatibledubpackage/dub.json" ]]; then
	die $LINENO 'Did not get dependencies installed into $DPATH.'
fi
