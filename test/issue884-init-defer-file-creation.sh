#!/usr/bin/env bash

set -e

TMPDIR=${CURR_DIR}tmppack
echo $TMPDIR

mkdir ${TMPDIR}
cd ${TMPDIR}

# kill dub init during interactive mode
${DUB} init < /dev/stdin &
sleep 1
kill $!

# ensure that no files are left behind
NFILES_PLUS_ONE=`ls -la | wc -l`

cd ${CURR_DIR}
rm -r ${TMPDIR}

# ignore sum + "." + ".."
if [ ${NFILES_PLUS_ONE} -gt 3 ]; then
	exit 1;
fi
