#!/usr/bin/env bash

set -e

. $(dirname "${BASH_SOURCE[0]}")/common.sh


BASEDIR=${CURR_DIR}/issue1372-ignore-files-in-hidden-dirs
rm -rf ${BASEDIR}/.dub
rm -rf ${BASEDIR}/issue1372

echo "Compile and ignore hidden directories"
${DUB} build --root ${BASEDIR} --config=normal --force
OUTPUT=`${BASEDIR}/issue1372`
if [[ "$OUTPUT" != "no hidden file compiled" ]]; then die "Normal compilation failed"; fi

rm -rf ${BASEDIR}/.dub
rm -rf ${BASEDIR}/issue1372


echo "Compile and explcitly include file in hidden directories"
${DUB} build --root ${BASEDIR} --config=hiddenfile --force
OUTPUT=`${BASEDIR}/issue1372`

if [[ "$OUTPUT" != "hidden file compiled" ]]; then die "Hidden file compilation failed"; fi

rm -rf ${BASEDIR}/.dub
rm -rf ${BASEDIR}/issue1372

echo "Compile and explcitly include extra hidden directories"
${DUB} build --root ${BASEDIR} --config=hiddendir --force
OUTPUT=`${BASEDIR}/issue1372`

if [[ "$OUTPUT" != "hidden dir compiled" ]]; then die "Hidden directory compilation failed"; fi

rm -rf ${BASEDIR}/.dub
rm -rf ${BASEDIR}/issue1372
