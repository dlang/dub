#!/usr/bin/env bash

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "${CURR_DIR}/failed-json-1"

temp_file="$(mktemp)"

trap "rm \"$temp_file\"" EXIT

if "${DUB}" 2>"$temp_file"; then
    die $LINENO "Dub expected to fail but succeeded!"
fi
EXPECTED_MSG="'.sourcePaths': Expected JSON array, got string"
if [[ "$(cat "$temp_file")" != "$EXPECTED_MSG" ]]; then
    die $LINENO "Expected: \"$EXPECTED_MSG\", Actual: \"$(cat "$temp_file")\""
fi

cd "${CURR_DIR}/failed-json-2"

temp_file="$(mktemp)"

trap "rm \"$temp_file\"" EXIT

if "${DUB}" 2>"$temp_file"; then
    die $LINENO "Dub expected to fail but succeeded!"
fi
EXPECTED_MSG="'.subConfigurations': Expected JSON object, got array"
if [[ "$(cat "$temp_file")" != "$EXPECTED_MSG" ]]; then
    die $LINENO "Expected: \"$EXPECTED_MSG\", Actual: \"$(cat "$temp_file")\""
fi

