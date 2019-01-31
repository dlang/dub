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


$DUB init --non-interactive --format=json $tempDir
cd $tempDir

echo "import gitcompatibledubpackage.subdir.file; void main(){}" > source/app.d
$DUB add gitcompatibledubpackage --skip-registry=all --registry=http://localhost:$PORT
grep -q '"gitcompatibledubpackage"\s*:\s*"~>1\.0\.4"' dub.json
$DUB add gitcompatibledubpackage=1.0.2 non-existing-issue1574-pkg='~>9.8.7' --skip-registry=all
grep -q '"gitcompatibledubpackage"\s*:\s*"1\.0\.2"' dub.json
grep -q '"non-existing-issue1574-pkg"\s*:\s*"~>9\.8\.7"' dub.json
if $DUB add foo@1.2.3 gitcompatibledubpackage='~>a.b.c' --skip-registry=all; then
    die $LINENO 'Adding non-semver spec should error'
fi
if grep -q '"foo"' dub.json; then
    die $LINENO 'Failing add command should not write recipe file'
fi
