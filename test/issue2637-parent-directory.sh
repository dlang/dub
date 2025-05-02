#!/usr/bin/env bash

set -e

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd "${CURR_DIR}/issue2637-parent-directory"
test ! -e bad || rmdir bad
mkdir -m 000 bad
trap 'rmdir bad' EXIT

(
	cd pkg
	$DUB run
)
