#!/usr/bin/env bash
DIR=$(dirname "${BASH_SOURCE[0]}")

. "$DIR"/common.sh

PORT=$(($$ + 1024)) # PID + 1024

dub remove gitcompatibledubpackage --non-interactive --version=* 2>/dev/null || true

"$DUB" build --single "$DIR"/test_registry.d
"$DIR"/test_registry --folder="$DIR/issue1336-registry" --port=$PORT &
PID=$!
sleep 1
trap 'kill $PID 2>/dev/null || true' exit

echo "Trying to download gitcompatibledubpackage (1.0.4)"
timeout 1s "$DUB" fetch gitcompatibledubpackage --version=1.0.4 --skip-registry=all --registry=http://localhost:$PORT
if [ $? -eq 124 ]; then
    die 'Fetching from responsive registry should not time-out.'
fi
dub remove gitcompatibledubpackage --non-interactive --version=1.0.4

echo "Downloads should be retried when the zip is corrupted - gitcompatibledubpackage (1.0.3)"
zipOut=$(! timeout 1s "$DUB" fetch gitcompatibledubpackage --version=1.0.3 --skip-registry=all --registry=http://localhost:$PORT 2>&1)
rc=$?

if ! zipCount=$(grep -Fc 'Failed to extract zip archive' <<<"$zipOut") || [ "$zipCount" -lt 3 ] ; then
    echo '========== +Output was ==========' >&2
    echo "$zipOut" >&2
    echo '========== -Output was ==========' >&2
    die 'DUB should have tried to download the zip archive multiple times.'
elif [ $rc -eq 124 ]; then
    die 'DUB timed out unexpectedly.'
fi
if dub remove gitcompatibledubpackage --non-interactive --version=* 2>/dev/null; then
    die 'DUB should not have installed a broken package.'
fi

echo "HTTP status errors on downloads should be retried - gitcompatibledubpackage (1.0.2)"
retryOut=$(! timeout 1s "$DUB" fetch gitcompatibledubpackage --version=1.0.2 --skip-registry=all --registry=http://localhost:$PORT --vverbose 2>&1)
rc=$?
if ! retryCount=$(echo "$retryOut" | grep -Fc 'Bad Gateway') || [ "$retryCount" -lt 3 ] ; then
    echo '========== +Output was ==========' >&2
    echo "$retryOut" >&2
    echo '========== -Output was ==========' >&2
    die "DUB should have retried download on server error multiple times, but only tried $retryCount times."
elif [ $rc -eq 124 ]; then
    die 'DUB timed out unexpectedly.'
fi
if dub remove gitcompatibledubpackage --non-interactive --version=* 2>/dev/null; then
    die 'DUB should not have installed a package.'
fi

echo "HTTP status errors on downloads should retry with fallback mirror - gitcompatibledubpackage (1.0.2)"
timeout 1s "$DUB" fetch gitcompatibledubpackage --version=1.0.2 --skip-registry=all --registry="http://localhost:$PORT http://localhost:$PORT/fallback"
if [ $? -eq 124 ]; then
    die 'Fetching from responsive registry should not time-out.'
fi
dub remove gitcompatibledubpackage --non-interactive --version=1.0.2
