#!/usr/bin/env bash

set -e

TMPDIR=${CURR_DIR}tmppack
echo $TMPDIR

mkdir ${TMPDIR}
cd ${TMPDIR}

nothing() {
	tail -f /dev/null &
	sleep 2
	kill $!
}

# kill dub init during interactive mode
# Use stdin if we're in a terminal,
# otherwise use the endlessly empty
# `nothing` function above
if [ -t 0 ]; then
	${DUB} init < /dev/stdin &
else
	${DUB} init < <(nothing) &
fi
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
