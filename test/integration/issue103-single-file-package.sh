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
${DUB} ./issue103-single-file-package foo -- bar
./issue103-single-file-package-no-ext foo -- bar

${DUB} issue103-single-file-package-w-dep.d

if [ -f single-file-test ]; then
	die $LINENO 'Shebang invocation produced binary in current directory'
fi

if ! { ${DUB} run --single issue103-single-file-package-w-dep.d --temp-build 2>&1 || true; } | grep -cF "To force a rebuild"; then
	echo "Invocation triggered unnecessary rebuild."
	exit 1
fi

if ${DUB} "issue103-single-file-package-error.d" 2> /dev/null; then
	echo "Invalid package comment syntax did not trigger an error."
	exit 1
fi
