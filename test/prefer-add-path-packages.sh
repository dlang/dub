#!/usr/bin/env bash

. $(dirname ${BASH_SOURCE[0]})/common.sh

TMPDIR=$CURR_DIR/tmp-add-path

PACK_PATH="$CURR_DIR"/issue2262-exact-cached-version-match

# make sure that there are no left-over selections files or temp directory
rm -f $PACK_PATH/dub.selections.json
rm -rf $TMPDIR

# make sure that there are no cached versions of the dependency
$DUB remove gitcompatibledubpackage@* -n || true

# build normally, should select 1.0.4
if ! ${DUB} build --root $PACK_PATH | grep "gitcompatibledubpackage 1\.0\.4:"; then
    die $LINENO 'The initial build failed.'
fi

# clone gitcompatibledubpackage and check out 1.0.4+commit.2.ccb31bf
mkdir $TMPDIR
$DUB add-path $TMPDIR
cd $TMPDIR
git clone https://github.com/dlang-community/gitcompatibledubpackage.git
cd gitcompatibledubpackage
git checkout -q ccb31bf6a655437176ec02e04c2305a8c7c90d67
cd ../..

if ! $DUB list | grep "gitcompatibledubpackage 1\.0\.4+commit.2.gccb31bf"; then
    $DUB remove-path $TMPDIR
    die $LINENO 'Cloned package was not found in search path'
fi

# should pick up the cloned package instead of the cached one now
if ! ${DUB} build --root $PACK_PATH | grep "gitcompatibledubpackage 1\.0\.4+commit.2.gccb31bf:"; then
    $DUB remove-path $TMPDIR
    die $LINENO 'Did not pick up the add-path package.'
fi

# clean up
$DUB remove-path $TMPDIR
rm -f $PACK_PATH/dub.selections.json
rm -rf $TMPDIR
