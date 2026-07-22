#!/usr/bin/env bash
set -e

. $(dirname "${BASH_SOURCE[0]}")/common.sh

if [ -f issue208-generate-cwd-root.sln ] || [ -f .dub/issue208-generate-cwd-root.visualdproj]; then
	die $LINENO 'Did not expect VisualD files for this test to exist in the working directory'
fi

function cleanup {
    rm -rf "$CURR_DIR/issue208-generate-cwd-root"
}

mkdir "$CURR_DIR/issue208-generate-cwd-root"

trap cleanup EXIT

pushd "$CURR_DIR/issue208-generate-cwd-root"

$DUB init -n

popd

$DUB generate visuald --root="$CURR_DIR/issue208-generate-cwd-root"

if [ -f issue208-generate-cwd-root.sln ] || [ -f .dub/issue208-generate-cwd-root.visualdproj ]; then
	rm -f issue208-generate-cwd-root.sln .dub/issue208-generate-cwd-root.visualdproj
	die $LINENO 'VisualD files were generated in CWD instead of inside package directory'
fi

if [ ! -f "$CURR_DIR/issue208-generate-cwd-root/issue208-generate-cwd-root.sln" ] then
	die $LINENO 'no VisualD files were generated in target package directory'
fi

# TODO: when the tests above work, make sure the paths in the generated
# .visualdproj file are all relative to the package, and not relative to $CURR_DIR
