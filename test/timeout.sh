#!/usr/bin/env bash
set -euo pipefail

. $(dirname "${BASH_SOURCE[0]}")/common.sh

PORT=$(getRandomPort)

# The outer `timeout` budgets are generous on purpose: they only serve to
# catch hangs. The checks are about DUB's internal timeouts (default 8s)
# and error handling, and DUB startup alone (especially in coverage builds)
# can take a second or two on slow runners.

log '    Testing unconnectable registry'
rc=0
timeout 30s $DUB fetch dub --skip-registry=all --registry=http://localhost:$PORT || rc=$?
if [ $rc -eq 0 ]; then
    die $LINENO 'Fetching from unconnectable registry should fail.'
elif [ $rc -eq 124 ]; then
    die $LINENO 'Fetching from unconnectable registry should fail fast (connection refused).'
fi

log '    Testing non-responding registry'
cat | nc -l $PORT >/dev/null &
PID=$!
rc=0
timeout 30s $DUB fetch dub --skip-registry=all --registry=http://localhost:$PORT || rc=$?
if [ $rc -eq 0 ]; then
    die $LINENO 'Fetching from non-responding registry should fail.'
elif [ $rc -eq 124 ]; then
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
rc=0
timeout 30s time $DUB fetch dub --skip-registry=all --registry=http://localhost:$PORT || rc=$?
if [ $rc -eq 0 ]; then
    die $LINENO 'Fetching from too slow registry should fail.'
elif [ $rc -eq 124 ]; then
    die $LINENO 'Fetching from too slow registry should time-out within 8s.'
fi
kill $PID 2>/dev/null || true
