#!/bin/sh
set -e
cd ${CURR_DIR}
./issue103-single-file-package.d foo -- bar
${DUB} run --single issue103-single-file-package-json.d --compiler=${DC}
${DUB} issue103-single-file-package-w-dep.d --compiler=${DC}
