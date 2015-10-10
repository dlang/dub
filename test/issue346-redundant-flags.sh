#!/bin/sh

cd ${CURR_DIR}/issue346-redundant-flags
${DUB} build --bare --force --compiler=${DC} -a x86 main | grep -e "-m32 -m32" 2>&1 && exit 1 || exit 0
