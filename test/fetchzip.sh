#!/bin/bash
DIR=$(dirname "${BASH_SOURCE[0]}")

. "$DIR"/common.sh

PORT=$(($$ + 1024)) # PID + 1024

rm -rf "$HOME"/.dub/packages/gitcompatibledubpackage-*

"$DUB" build --single "$DIR"/test_registry.d
"$DIR"/test_registry --folder="$DIR/issue1336-registry" --port=$PORT &
PID=$!
sleep 0.2
trap 'kill $PID 2>/dev/null || true' exit

echo "Trying to download gitcompatibledubpackage (1.0.4)"
timeout 1s "$DUB" -v fetch gitcompatibledubpackage --version=1.0.4 --skip-registry=all --registry=http://localhost:$PORT
if [ $? -eq 124 ]; then
    die 'Fetching from responsive registry should not time-out.'
fi

echo "Trying to download gitcompatibledubpackage (1.0.3) from a broken registry"
zipCount=$(! "$DUB" -v fetch gitcompatibledubpackage --version=1.0.3 --skip-registry=all --registry=http://localhost:$PORT 2>&1| grep -c 'Failed to extract zip archive')
if [  "$zipCount" -le 3 ] ; then
    die 'DUB should have tried to download the zip archive multiple times.'
elif [ $? -eq 124 ]; then
    die 'DUB timed out unexpectedly.'
fi
