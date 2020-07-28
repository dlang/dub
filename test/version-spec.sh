#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

$DUB add-local "$CURR_DIR/version-spec/newfoo"
$DUB add-local "$CURR_DIR/version-spec/oldfoo"

[[ $($DUB describe foo | grep path | head -1) == *"/newfoo/"* ]] || false
[[ $($DUB describe foo@1.0.0 | grep path | head -1) == *"/newfoo/"* ]] || false
[[ $($DUB describe foo@0.1.0 | grep path | head -1) == *"/oldfoo/"* ]] || false

[[ $($DUB test foo | head -1) == *"/newfoo/" ]] || false
[[ $($DUB test foo@1.0.0 | head -1) == *"/newfoo/" ]] || false
[[ $($DUB test foo@0.1.0 | head -1) == *"/oldfoo/" ]] || false

[[ $($DUB lint foo | tail -1) == *"/newfoo/" ]] || false
[[ $($DUB lint foo@1.0.0 | tail -1) == *"/newfoo/" ]] || false
[[ $($DUB lint foo@0.1.0 | tail -1) == *"/oldfoo/" ]] || false

[[ $($DUB generate cmake foo | head -1) == *"/newfoo/" ]] || false
[[ $($DUB generate cmake foo@1.0.0 | head -1) == *"/newfoo/" ]] || false
[[ $($DUB generate cmake foo@0.1.0 | head -1) == *"/oldfoo/" ]] || false

[[ $($DUB build -n foo | head -1) == *"/newfoo/" ]] || false
[[ $($DUB build -n foo@1.0.0 | head -1) == *"/newfoo/" ]] || false
[[ $($DUB build -n foo@0.1.0 | head -1) == *"/oldfoo/" ]] || false

[[ $($DUB run -n foo | tail -1) == 'new-foo' ]] || false
[[ $($DUB run -n foo@1.0.0 | tail -1) == 'new-foo' ]] || false
[[ $($DUB run -n foo@0.1.0 | tail -1) == 'old-foo' ]] || false

$DUB remove-local "$CURR_DIR/version-spec/newfoo"
$DUB remove-local "$CURR_DIR/version-spec/oldfoo"