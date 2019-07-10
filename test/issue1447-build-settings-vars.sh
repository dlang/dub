#!/usr/bin/env bash
set -e

. $(dirname "${BASH_SOURCE[0]}")/common.sh

if [[ `uname -m` == "x86_64" ]]; then
    ARCH=x86_64
else
    ARCH=x86
fi

rm -rf ${CURR_DIR}/issue1447-build-settings-vars/.dub
rm -rf ${CURR_DIR}/issue1447-build-settings-vars/test

${DUB} build --root ${CURR_DIR}/issue1447-build-settings-vars --arch=$ARCH
OUTPUT=`${CURR_DIR}/issue1447-build-settings-vars/test`

rm -rf ${CURR_DIR}/issue1447-build-settings-vars/.dub
rm -rf ${CURR_DIR}/issue1447-build-settings-vars/test

if [[ "$OUTPUT" != "$ARCH" ]]; then die "Build settings ARCH var incorrect"; fi
