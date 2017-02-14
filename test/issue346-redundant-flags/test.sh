#!/bin/sh

${DUB} build --bare --force --compiler=${DC} -a x86_64 -v main 2>&1 | grep -e "-m64 -m64" -c && exit 1 || exit 0
