#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh
$DUB --root="$CURR_DIR/dub-as-a-library-cwd"
