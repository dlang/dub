#!/usr/bin/env bash
DIR=$(dirname "${BASH_SOURCE[0]}")

. "$DIR"/common.sh

PORT=$(getRandomPort)

dub remove maven-dubpackage --non-interactive --version=* 2>/dev/null || true

"$DUB" build --single "$DIR"/test_registry.d
"$DIR"/test_registry --folder="$DIR/issue1416-maven-repo-pkg-supplier" --port=$PORT &
PID=$!
sleep 1
trap 'kill $PID 2>/dev/null || true' exit

echo "Trying to download maven-dubpackage (1.0.5)"
"$DUB" fetch maven-dubpackage --version=1.0.5 --skip-registry=all --registry=mvn+http://localhost:$PORT/maven/release/dubpackages

if ! dub remove maven-dubpackage --non-interactive --version=1.0.5 2>/dev/null; then
    die 'DUB did not install package from maven registry.'
fi

echo "Trying to download maven-dubpackage (latest)"
"$DUB" fetch maven-dubpackage --skip-registry=all --registry=mvn+http://localhost:$PORT/maven/release/dubpackages

if ! dub remove maven-dubpackage --non-interactive --version=1.0.6 2>/dev/null; then
    die 'DUB fetch did not install latest package from maven registry.'
fi

echo "Trying to search (exact) maven-dubpackage"
"$DUB" search maven-dubpackage --skip-registry=all --registry=mvn+http://localhost:$PORT/maven/release/dubpackages | grep -c "maven-dubpackage (1.0.6)"
