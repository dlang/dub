#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh
$DUB build --root="$CURR_DIR/issue1691-build-subpkg" :subpkg
