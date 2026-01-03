#!/usr/bin/env bash

DIR=$(dirname "${BASH_SOURCE[0]}")

. "$DIR"/common.sh

# Test that search without arguments fails
if ${DUB} search 2>/dev/null; then
    die $LINENO '`dub search` succeeded'
fi

# Start the local test registry
PORT=$(getRandomPort)

${DUB} build --single "$DIR"/test_registry.d
"$DIR"/test_registry --folder="$DIR/feat663-search" --port=$PORT &
PID=$!
sleep 1
trap 'kill $PID 2>/dev/null || true' exit

# Test that search for nonexistent package returns no matches
if ${DUB} search nonexistent123456789package --skip-registry=all --registry=http://localhost:$PORT 2>/dev/null; then
    die $LINENO '`dub search nonexistent123456789package` succeeded'
fi

# Test that search for "dub-registry" succeeds and returns results
if ! OUTPUT=$(${DUB} search '"dub-registry"' -v --skip-registry=all --registry=http://localhost:$PORT 2>&1); then
    die $LINENO '`dub search "dub-registry"` failed' "$OUTPUT"
fi
if ! grep -q '^\s\sdub-registry (.*)\s'<<<"$OUTPUT"; then
    die $LINENO '`grep -q '"'"'^\s\sdub-registry (.*)\s'"'"'` failed' "$OUTPUT"
fi
