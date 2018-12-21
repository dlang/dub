#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue1117-extra-dependency-files


if ! { ${DUB} build 2>&1 || true; } | grep -cF 'building configuration'; then
	die $LINENO 'Build was not executed.'
fi

if ! { ${DUB} build 2>&1 || true; } | grep -cF 'is up to date'; then
	die $LINENO 'Build was executed.'
fi

touch ./dependency.txt

if ! { ${DUB} build 2>&1 || true; } | grep -cF 'building configuration'; then
	die $LINENO 'Build was not executed.'
fi
