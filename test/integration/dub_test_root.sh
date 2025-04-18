#!/usr/bin/env bash

# Make sure the auto-generated 'dub_test_root' module is importable for
# non-all-at-once compilations too.

set -euo pipefail

TMPDIR=$(mktemp -d "$(basename "$0").XXXXXX")

pushd "$TMPDIR"
function cleanup {
    popd
    rm -rf "$TMPDIR"
}
trap cleanup EXIT


echo 'name "foo"' > dub.sdl

mkdir -p source
echo 'import dub_test_root : allModules;' > source/foo.d

$DUB test --build-mode=singleFile
