#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue1773-lint
rm -rf report.json

if ! { ${DUB} lint || true; } | grep -cF "Parameter args is never used."; then
    die $LINENO 'DUB lint did not find expected warning.'
fi

${DUB} lint --report-file report.json
if ! grep -c -e "Parameter args is never used." report.json; then
	die $LINENO 'Linter report did not contain expected warning.'
fi
