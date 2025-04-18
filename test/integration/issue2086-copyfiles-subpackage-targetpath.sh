#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd "${CURR_DIR}/issue2086-copyfiles-subpackage-targetpath" || die "Could not cd."

rm -f "sub/to_be_deployed.txt"

"$DUB" build
./sub/sub
