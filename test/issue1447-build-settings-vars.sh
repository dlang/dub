#!/usr/bin/env bash
set -e

. $(dirname "${BASH_SOURCE[0]}")/common.sh

if [[ `uname -m` == "i386" ]]; then
    ARCH=x86
elif [[ `uname -m` == "i686" ]]; then
    ARCH=x86
elif [[ `uname -m` == "arm64" ]]; then
    ARCH="aarch64"
else
    ARCH=$(uname -m)
fi

rm -rf ${CURR_DIR}/issue1447-build-settings-vars/.dub
rm -rf ${CURR_DIR}/issue1447-build-settings-vars/test

${DUB} build --root ${CURR_DIR}/issue1447-build-settings-vars --arch=$ARCH
OUTPUT=`${CURR_DIR}/issue1447-build-settings-vars/test`

rm -rf ${CURR_DIR}/issue1447-build-settings-vars/.dub
rm -rf ${CURR_DIR}/issue1447-build-settings-vars/test

if [[ "$OUTPUT" != "$ARCH" ]]; then die $LINENO "Build settings ARCH var incorrect"; fi
