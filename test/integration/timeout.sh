#!/usr/bin/env bash
set -euo pipefail

. $(dirname "${BASH_SOURCE[0]}")/common.sh

PORT=$(getRandomPort)

log '    Testing unconnectable registry'
if timeout 1s $DUB fetch dub --skip-registry=all --registry=http://localhost:$PORT; then
    die $LINENO 'Fetching from unconnectable registry should fail.'
elif [ $? -eq 124 ]; then
    die $LINENO 'Fetching from unconnectable registry should fail immediately.'
fi

log '    Testing non-responding registry'
cat | nc -l $PORT >/dev/null &
PID=$!
if timeout 10s $DUB fetch dub --skip-registry=all --registry=http://localhost:$PORT; then
    die $LINENO 'Fetching from non-responding registry should fail.'
elif [ $? -eq 124 ]; then
    die $LINENO 'Fetching from non-responding registry should time-out within 8s.'
fi
kill $PID 2>/dev/null || true

log '    Testing too slow registry'
{
    res=$(printf 'HTTP/1.1 200 OK\r
Server: dummy\r
Content-Type: application/json\r
Content-Length: 2\r
\r
{}')
    for i in $(seq 0 $((${#res} - 1))); do
        echo -n "${res:$i:1}" || true
        sleep 1
    done
} | tail -n +1 | nc -l $PORT >/dev/null &
PID=$!
if timeout 10s time $DUB fetch dub --skip-registry=all --registry=http://localhost:$PORT; then
    die $LINENO 'Fetching from too slow registry should fail.'
elif [ $? -eq 124 ]; then
    die $LINENO 'Fetching from too slow registry should time-out within 8s.'
fi
kill $PID 2>/dev/null || true
