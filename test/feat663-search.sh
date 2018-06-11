#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
if ${DUB} search 2>/dev/null; then
    die $LINENO '`dub search` succeeded'
fi
if ${DUB} search nonexistent123456789package 2>/dev/null; then
    die $LINENO '`dub search nonexistent123456789package` succeeded'
fi
if ! OUTPUT=$(${DUB} search dub -v 2>&1); then
    die $LINENO '`dub search dub` failed' "$OUTPUT"
fi
if ! grep -q '^\s*dub (.*)\s'<<<"$OUTPUT"; then
    die $LINENO '`grep -q '"'"'^\s*dub (.*)\s'"'"'` failed' "$OUTPUT"
fi
