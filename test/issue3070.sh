#!/usr/bin/env bash
# Test for https://github.com/dlang/dub/issues/3070
# Verify mixed path separators don't cause duplicate source file errors.
set -e
. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue3070
$DUB build --compiler=${DC} 2>&1
echo "PASS: No duplicate source file error with mixed path separators."