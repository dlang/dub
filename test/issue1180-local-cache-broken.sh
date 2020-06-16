#!/usr/bin/env bash
DIR=$(dirname "${BASH_SOURCE[0]}")

. "$DIR"/common.sh

PORT=$(getRandomPort)

"$DUB" remove maven-dubpackage --root="$DIR/issue1180-local-cache-broken" --non-interactive --version=* 2>/dev/null || true

"$DUB" build --single "$DIR"/test_registry.d
"$DIR"/test_registry --folder="$DIR/issue1416-maven-repo-pkg-supplier" --port=$PORT &
PID=$!
sleep 1
trap 'kill $PID 2>/dev/null || true' exit

echo "Trying to download maven-dubpackage (1.0.5)"
"$DUB" upgrade --root="$DIR/issue1180-local-cache-broken" --cache=local --skip-registry=all --registry=mvn+http://localhost:$PORT/maven/release/dubpackages

if ! "$DUB" remove maven-dubpackage --root="$DIR/issue1180-local-cache-broken" --non-interactive --version=1.0.5 2>/dev/null; then
    die 'DUB did not install package from maven registry.'
fi
