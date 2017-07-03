#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue346-redundant-flags
${DUB} build --bare --force --compiler=${DC} -a x86_64 -v main 2>&1 | grep -e "-m64 -m64" -c && exit 1 || exit 0
