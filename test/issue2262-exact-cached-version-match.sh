#!/usr/bin/env bash

. $(dirname ${BASH_SOURCE[0]})/common.sh

PACK_PATH="$CURR_DIR"/issue2262-exact-cached-version-match

# make sure that there are no left-over selections files
rm -f $PACK_PATH/dub.selections.json

# make sure that there are no cached versions of the dependency
dub remove gitcompatibledubpackage@* -n || true

# build normally, should select 1.0.4
if ! ${DUB} build --root $PACK_PATH | grep "gitcompatibledubpackage 1\.0\.4:"; then
    die $LINENO 'The initial build failed.'
fi
dub remove gitcompatibledubpackage@* -n || true

# build with git dependency to a specific commit
cat > $PACK_PATH/dub.selections.json << EOF
{
    "fileVersion": 1,
    "versions": {
        "gitcompatibledubpackage": {
            "repository": "git+https://github.com/dlang-community/gitcompatibledubpackage.git",
            "version": "ccb31bf6a655437176ec02e04c2305a8c7c90d67"
        }
    }
}
EOF
if ! ${DUB} build --root $PACK_PATH | grep "gitcompatibledubpackage 1\.0\.4+commit\.2\.gccb31bf:"; then
    die $LINENO 'The build with a specific commit failed.'
fi

# select 1.0.4 again
cat > $PACK_PATH/dub.selections.json << EOF
{
    "fileVersion": 1,
    "versions": {
        "gitcompatibledubpackage": "1.0.4"
    }
}
EOF
if ! ${DUB} build --root $PACK_PATH | grep "gitcompatibledubpackage 1\.0\.4:"; then
    die $LINENO 'The second 1.0.4 build failed.'
fi

# clean up
rm -f $PACK_PATH/dub.selections.json
