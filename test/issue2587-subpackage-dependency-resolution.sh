#!/usr/bin/env bash

set -e

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd "${CURR_DIR}/issue2587-subpackage-dependency-resolution/a"

rm -f dub.selections.json
$DUB upgrade -v
$DUB run

rm -f dub.selections.json
$DUB run
