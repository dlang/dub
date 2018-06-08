#!/usr/bin/env bash
DIR=$(dirname "${BASH_SOURCE[0]}")

. "$DIR"/common.sh

PORT=$(($$ + 1024)) # PID + 1024

dub remove package1489 --non-interactive --version=* 2>/dev/null || true

"$DUB" build --single "$DIR"/test_registry.d
"$DIR"/test_registry --folder="$DIR/issue1489-maven-snapshot-repo" --port=$PORT &
PID=$!
sleep 1
trap 'kill $PID 2>/dev/null || true' exit


DUB_WORKDIR="$DIR/issue1489-maven-snapshot-repo/app1489"
"$DUB" build --root "$DUB_WORKDIR" --skip-registry=all --registry=mvn+http://localhost:$PORT/version1/snapshots/dubpackages
"$DUB" run --root "$DUB_WORKDIR" --vquiet | grep -c "snapshot1" > /dev/null

"$DUB" upgrade --root "$DUB_WORKDIR" --skip-registry=all --registry=mvn+http://localhost:$PORT/version2/snapshots/dubpackages
"$DUB" run --root "$DUB_WORKDIR" --vquiet | grep -c "snapshot2" > /dev/null

