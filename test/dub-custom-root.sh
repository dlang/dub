#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh

pushd "$CURR_DIR"

$DUB --root=dub-custom-root

$DUB --root=dub-custom-root-2

popd
