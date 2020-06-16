#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

if ! [ -d ${CURR_DIR}/issue1040-tmpdir ]; then
	mkdir ${CURR_DIR}/issue1040-tmpdir
	touch ${CURR_DIR}/issue1040-tmpdir/.no_build
	touch ${CURR_DIR}/issue1040-tmpdir/.no_run
	touch ${CURR_DIR}/issue1040-tmpdir/.no_test
	function cleanup {
		rm -rf ${CURR_DIR}/issue1040-tmpdir
	}
	trap cleanup EXIT
fi

cd ${CURR_DIR}/issue1040-tmpdir

$DUB fetch dub@1.17.0 --cache=local
$DUB fetch dub@1.18.0 --cache=local
$DUB fetch dub@1.19.0 --cache=local

if { $DUB fetch dub@1.18.0 --cache=local || true; } | grep -cF 'Fetching' > /dev/null; then
	die $LINENO 'Test for doubly fetch of the specified version has failed.'
fi
if ! { $DUB run dub -q --cache=local -- --version || true; } | grep -cF 'DUB version 1.19.0' > /dev/null; then
	die $LINENO 'Test for selection of the latest fetched version has failed.'
fi
if ! { $DUB run dub@1.18.0 -q --cache=local -- --version || true; } | grep -cF 'DUB version 1.18.0' > /dev/null; then
	die $LINENO 'Test for selection of the specified version has failed.'
fi
