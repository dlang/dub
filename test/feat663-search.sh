#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
if ${DUB} search 2>/dev/null; then
    die $LINENO '`dub search` succeeded'
fi
if ${DUB} search nonexistent123456789package 2>/dev/null; then
    die $LINENO '`dub search nonexistent123456789package` succeeded'
fi
if ! OUTPUT=$(${DUB} search '"dub-registry"' -v 2>&1); then
    die $LINENO '`dub search "dub-registry"` failed' "$OUTPUT"
fi
if ! grep -q '^\s\sdub-registry (.*)\s'<<<"$OUTPUT"; then
    die $LINENO '`grep -q '"'"'^\s\sdub-registry (.*)\s'"'"'` failed' "$OUTPUT"
fi
