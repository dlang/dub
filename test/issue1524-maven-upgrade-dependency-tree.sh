#!/usr/bin/env bash
DIR=$(dirname "${BASH_SOURCE[0]}")

. "$DIR"/common.sh

PORT=$(getRandomPort)

dub remove maven-dubpackage-a --non-interactive 2>/dev/null || true
dub remove maven-dubpackage-b --non-interactive 2>/dev/null || true

"$DUB" build --single "$DIR"/test_registry.d
"$DIR"/test_registry --folder="$DIR/issue1524-maven-upgrade-dependency-tree" --port=$PORT &
PID=$!
sleep 1
trap 'kill $PID 2>/dev/null || true' exit

echo "Trying to download maven-dubpackage-a (1.0.5) with dependency to maven-dubpackage-b (1.0.6)"
"$DUB" upgrade --root "$DIR/issue1524-maven-upgrade-dependency-tree" --skip-registry=standard --registry=mvn+http://localhost:$PORT/maven/release/dubpackages

if ! dub remove maven-dubpackage-a --non-interactive --version=1.0.5 2>/dev/null; then
    die 'DUB did not install package "maven-dubpackage-a" from maven registry.'
fi

if ! dub remove maven-dubpackage-b --non-interactive --version=1.0.6 2>/dev/null; then
    die 'DUB did not install package "maven-dubpackage-b" from maven registry.'
fi

