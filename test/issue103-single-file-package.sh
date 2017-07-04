#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}
rm -f single-file-test

${DUB} run --single issue103-single-file-package-json.d --compiler=${DC}
if [ ! -f single-file-test ]; then
	die $LINENO 'Normal invocation did not produce a binary in the current directory'
fi
rm single-file-test

./issue103-single-file-package.d foo -- bar

${DUB} issue103-single-file-package-w-dep.d

if [ -f single-file-test ]; then
	die $LINENO 'Shebang invocation produced binary in current directory'
fi
