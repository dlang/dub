#!/usr/bin/env bash

set -euo pipefail

TMPDIR=$(mktemp -d "$(basename "$0").XXXXXX")

function cleanup {
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

# no unittest config
cat > "$TMPDIR/no_ut.d" <<EOF
/+ dub.sdl:
name "no_ut"
targetType "library"
+/
void foo() {}
EOF
$DUB describe --single "$TMPDIR/no_ut.d" --config=unittest | grep -q '"targetName": "no_ut-test-library"'
$DUB build    --single "$TMPDIR/no_ut.d" --config=unittest --build=unittest
"$TMPDIR/no_ut-test-library"

# partial unittest config - targetPath only
cat > "$TMPDIR/partial_ut.d" <<EOF
/+ dub.sdl:
name "partial_ut"
targetType "library"
configuration "unittest" {
    targetPath "bin"
}
+/
void foo() {}
EOF
$DUB describe --single "$TMPDIR/partial_ut.d" --config=unittest | grep -q '"targetName": "partial_ut-test-unittest"'
$DUB build    --single "$TMPDIR/partial_ut.d" --config=unittest --build=unittest
"$TMPDIR/bin/partial_ut-test-unittest"

# partial unittest config - targetPath & targetName
cat > "$TMPDIR/partial_ut2.d" <<EOF
/+ dub.sdl:
name "partial_ut2"
targetType "library"
configuration "unittest" {
    targetPath "bin"
    targetName "ut"
}
+/
void foo() {}
EOF
$DUB describe --single "$TMPDIR/partial_ut2.d" --config=unittest | grep -q '"targetName": "ut"'
$DUB build    --single "$TMPDIR/partial_ut2.d" --config=unittest --build=unittest
"$TMPDIR/bin/ut"

# full unittest config (i.e., `executable` target type)
cat > "$TMPDIR/full_ut.d" <<EOF
/+ dub.sdl:
name "full_ut"
targetType "library"
configuration "unittest" {
    targetType "executable"
    targetPath "bin"
}
+/
void main() {}
EOF
$DUB describe --single "$TMPDIR/full_ut.d" --config=unittest | grep -q '"targetName": "full_ut"'
$DUB build    --single "$TMPDIR/full_ut.d" --config=unittest --build=unittest
"$TMPDIR/bin/full_ut"
