#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/removed-dub-obj

DUB_CACHE_PATH="$HOME/.dub/cache/removed-dub-obj"

rm -rf "$DUB_CACHE_PATH"

${DUB} build --compiler=${DC}

[ -d "$DUB_CACHE_PATH" ] || die $LINENO "$DUB_CACHE_PATH not found"

numObjectFiles=$(find "$DUB_CACHE_PATH" -type f -iname '*.o*' | wc -l)
# note: fails with LDC < v1.1
[ "$numObjectFiles" -eq 0 ] || die $LINENO "Found left-over object files in $DUB_CACHE_PATH"
