#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}
rm -f libsingle-file-test-dynamic-library.{so,dylib}
rm -f single-file-test-dynamic-library.dll

${DUB} build --single issue1505-single-file-package-dynamic-library.d
if [ ! -f libsingle-file-test-dynamic-library.{so,dylib} ] && [ ! -f single-file-test-dynamic-library.dll ]; then
	die $LINENO 'Normal invocation did not produce a dynamic library in the current directory'
fi
rm -f libsingle-file-test-dynamic-library.{so,dylib}
rm -f single-file-test-dynamic-library.dll
