#!/usr/bin/env bash
set -euxo pipefail

DIR=$(dirname "${BASH_SOURCE[0]}")

. "$DIR"/common.sh

PORT=$(getRandomPort)

${DUB} remove gitcompatibledubpackage --non-interactive 2>/dev/null || true

${DUB} build --single "$DIR"/test_registry.d
"$DIR"/test_registry --folder="$DIR/issue1336-registry" --port=$PORT &
PID=$!
sleep 1
trap 'kill $PID 2>/dev/null || true' exit

# Timeouts are generous on purpose: they are only meant to catch hangs.
# DUB startup alone (especially in coverage builds) can take a second or two.
echo "Trying to download gitcompatibledubpackage (1.0.4)"
rc=0
timeout 60s ${DUB} fetch gitcompatibledubpackage@1.0.4 --skip-registry=all --registry=http://localhost:$PORT || rc=$?
if [ $rc -eq 124 ]; then
    die $LINENO 'Fetching from responsive registry should not time-out.'
elif [ $rc -ne 0 ]; then
    die $LINENO "Fetching failed with status code ${rc}."
fi
${DUB} remove gitcompatibledubpackage@1.0.4

echo "Downloads should be retried when the zip is corrupted - gitcompatibledubpackage (1.0.3)"
rc=0
zipOut=$(timeout 60s ${DUB} fetch gitcompatibledubpackage@1.0.3 --skip-registry=all --registry=http://localhost:$PORT 2>&1) || rc=$?
if [ $rc -eq 0 ]; then
    die $LINENO 'DUB should not have fetched a corrupted zip archive.'
elif [ $rc -eq 124 ]; then
    die $LINENO 'DUB timed out unexpectedly.'
fi

if ! zipCount=$(grep -Fc 'Failed to extract zip archive' <<<"$zipOut") || [ "$zipCount" -lt 3 ] ; then
    echo '========== +Output was ==========' >&2
    echo "$zipOut" >&2
    echo '========== -Output was ==========' >&2
    die $LINENO 'DUB should have tried to download the zip archive multiple times.'
fi
if ${DUB} remove gitcompatibledubpackage --non-interactive 2>/dev/null; then
    die $LINENO 'DUB should not have installed a broken package.'
fi

echo "HTTP status errors on downloads should be retried - gitcompatibledubpackage (1.0.2)"
rc=0
retryOut=$(timeout 60s ${DUB} fetch gitcompatibledubpackage@1.0.2 --skip-registry=all --registry=http://localhost:$PORT --vverbose 2>&1) || rc=$?
if [ $rc -eq 0 ]; then
    die $LINENO 'DUB should not have fetched from a registry only answering with errors.'
elif [ $rc -eq 124 ]; then
    die $LINENO 'DUB timed out unexpectedly.'
fi
if ! retryCount=$(echo "$retryOut" | grep -Fc 'Bad Gateway') || [ "$retryCount" -lt 3 ] ; then
    echo '========== +Output was ==========' >&2
    echo "$retryOut" >&2
    echo '========== -Output was ==========' >&2
    die $LINENO "DUB should have retried download on server error multiple times, but only tried $retryCount times."
fi
if ${DUB} remove gitcompatibledubpackage --non-interactive 2>/dev/null; then
    die $LINENO 'DUB should not have installed a package.'
fi

echo "HTTP status errors on downloads should retry with fallback mirror - gitcompatibledubpackage (1.0.2)"
rc=0
timeout 60s "$DUB" fetch gitcompatibledubpackage@1.0.2 --skip-registry=all --registry="http://localhost:$PORT http://localhost:$PORT/fallback" || rc=$?
if [ $rc -eq 124 ]; then
    die $LINENO 'Fetching from responsive registry should not time-out.'
elif [ $rc -ne 0 ]; then
    die $LINENO "Fetching failed with status code ${rc}."
fi
${DUB} remove gitcompatibledubpackage@1.0.2
