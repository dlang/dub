#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd "${CURR_DIR}/issue2085-target-none-visuald" || die "Could not cd."

"$DUB" generate visuald

if grep -c -e \"</Config>\" .dub/root.visualdproj; then
	die $LINENO 'Regression of issue #2085.'
fi
