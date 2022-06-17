#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd "${CURR_DIR}/selections-from-parent-dir/pkg2" || die "Could not cd."

"$DUB" build --nodeps

if [ -f dub.selections.json ]; then
    die "Shouldn't create a dub.selections.json in pkg2 subdir."
fi
