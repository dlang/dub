#!/usr/bin/env bash
DIR=$(dirname "${BASH_SOURCE[0]}")

. "$DIR"/common.sh

PORT=$(($$ + 1024)) # PID + 1024
tempDir="issue1574-addcommand"

"$DUB" build --single "$DIR"/test_registry.d
"$DIR"/test_registry --folder="$DIR/issue1336-registry" --port=$PORT &
PID=$!
sleep 1

function cleanup {
	cd ..
	rm -rf $tempDir
	kill $PID 2>/dev/null || true
}
trap cleanup EXIT


$DUB init -n $tempDir
cd $tempDir

echo "import gitcompatibledubpackage.subdir.file; void main(){}" > source/app.d

$DUB add gitcompatibledubpackage --skip-registry=all --registry=http://localhost:$PORT

#if dub fails to compile, that means that the "import mir.math.common" did not work
if ! $DUB build; then
	die "Add command failed"
fi
