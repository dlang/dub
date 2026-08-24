#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd "${CURR_DIR}/issue2618-targetType-none-run"

set +o pipefail

$DUB run --config dependencies --force 2>&1 | grep -c -F "Target is a library. Skipping execution."
