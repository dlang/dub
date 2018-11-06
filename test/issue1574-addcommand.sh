#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh

tempDir="issue1574-addcommand"

function cleanup {
	cd ..
	rm -rf $tempDir
}
trap cleanup EXIT


$DUB init -n $tempDir
cd $tempDir

echo "import mir.math.common; void main(){}" > source/app.d

$DUB add mir-core

#if dub fails to compile, that means that the "import mir.math.common" did not work
if ! $DUB build; then
	die "Add command failed"
fi
