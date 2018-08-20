#!/usr/bin/env bash
set -e

. $(dirname "${BASH_SOURCE[0]}")/common.sh

DIR1531=${CURR_DIR}/issue1531-min-dub-version

rm -rf $DIR1531/.dub/
rm -rf $DIR1531/test-application*

sed -i 's/^minDubVersion ".*"$/minDubVersion "1.0"/' ${DIR1531}/dub.sdl
${DUB} run --root ${DIR1531} || die "Did not pass minDubVersion \"1.0\""

sed -i 's/^minDubVersion ".*"$/minDubVersion "99.0"/' $DIR1531/dub.sdl
! ${DUB} run --root ${DIR1531} || die "Did pass minDubVersion \"99.0\"!"

sed -i 's/^minDubVersion ".*"$/minDubVersion "1.0"/' $DIR1531/dub.sdl
rm -rf $DIR1531/.dub/
rm -rf $DIR1531/test-application*
