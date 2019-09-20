#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh
DIR=$(dirname "${BASH_SOURCE[0]}")

if ! { ${DUB} lint --root ${DIR}/issue1773-lint || true; } | grep -cF "Parameter args is never used."; then
    die $LINENO 'DUB lint did not find expected warning.'
fi

