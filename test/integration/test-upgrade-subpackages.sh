#!/usr/bin/env bash

. $(dirname ${BASH_SOURCE[0]})/common.sh

PACK_PATH="$CURR_DIR"/path-subpackage-ref

# make sure that there are no left-over selections files
rm -f $PACK_PATH/dub.selections.json $PACK_PATH/subpack/dub.selections.json

# first upgrade only the root package
if ! ${DUB} upgrade --root $PACK_PATH; then
    die $LINENO 'The upgrade command failed.'
fi
if [ ! -f $PACK_PATH/dub.selections.json ] || [ -f $PACK_PATH/subpack/dub.selections.json ]; then
    die $LINENO 'The upgrade command did not generate the right set of dub.selections.json files.'
fi

rm -f $PACK_PATH/dub.selections.json

# now upgrade with all sub packages
if ! ${DUB} upgrade -s --root $PACK_PATH; then
    die $LINENO 'The upgrade command failed with -s.'
fi
if [ ! -f $PACK_PATH/dub.selections.json ] || [ ! -f $PACK_PATH/subpack/dub.selections.json ]; then
    die $LINENO 'The upgrade command did not generate all dub.selections.json files.'
fi

# clean up
rm -f $PACK_PATH/dub.selections.json $PACK_PATH/subpack/dub.selections.json
