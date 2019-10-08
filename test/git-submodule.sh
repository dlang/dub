#!/usr/bin/env bash
set -e

. $(dirname "${BASH_SOURCE[0]}")/common.sh

LAST_DIR=$PWD
TEMP_DIR="submodule-test"

function cleanup {
	cd "$LAST_DIR"
	rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir "$TEMP_DIR"
cd "$TEMP_DIR"

mkdir -p dependency/src

cat << EOF >> dependency/dub.sdl
name "dependency"
sourcePaths "src"
EOF

cat << EOF >> dependency/src/foo.d
module foo;
void foo() { }
EOF

function git_ {
	git -C dependency -c "user.name=Name" -c "user.email=Email" "$@"
}
git_ init
git_ add dub.sdl
git_ add src/foo.d
git_ commit -m "first commit"
git_ tag v1.0.0

mkdir project

cat << EOF >> project/dub.sdl
name "project"
mainSourceFile "project.d"
targetType "executable"
dependency "dependency" version="1.0.0"
EOF

cat << EOF >> project/project.d
module project;
import foo : foo;
void main() { foo(); }
EOF

function git_ {
	git -C project -c "user.name=Name" -c "user.email=Email" "$@"
}
git_ init
git_ add dub.sdl
git_ add project.d
git_ submodule add ../dependency dependency
git_ commit -m "first commit"

# dub should now pick up the dependency
$DUB --root=project --submodules run

if ! grep -c -e "\"dependency\": \"1.0.0\"" project/dub.selections.json; then
	die $LINENO "Dependency version was not identified correctly."
fi
