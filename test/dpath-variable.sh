#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
export DPATH="${CURR_DIR}/dpath-variable/dpath"
rm -rf "$DPATH"
cd "${CURR_DIR}/dpath-variable"
"${DUB}" upgrade

if [[ ! -f "$DPATH/dub/packages/gitcompatibledubpackage-1.0.1/gitcompatibledubpackage/dub.json" ]]; then
	die $LINENO 'Did not get dependencies installed into $DPATH.'
fi

# just for making this shell script easier to write, copy the variable
DPATH_ALIAS="$DPATH"
# unset the variable so DUB doesn't pick it up though
unset DPATH
rm -rf "$DPATH_ALIAS"
echo '{"dubHome":"'"$DPATH_ALIAS"/dub2'"}' > "${CURR_DIR}/dpath-variable/dub.settings.json"

function cleanup {
	rm "${CURR_DIR}/dpath-variable/dub.settings.json"
}
trap cleanup EXIT

"${DUB}" upgrade

if [[ ! -f "$DPATH_ALIAS/dub2/packages/gitcompatibledubpackage-1.0.1/gitcompatibledubpackage/dub.json" ]]; then
	die $LINENO 'Did not get dependencies installed into dubHome (set from config).'
fi
