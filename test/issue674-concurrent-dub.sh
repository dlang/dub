#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

TMPDIR=$(mktemp -d $(basename $0).XXXXXX)

function cleanup {
    rm -rf ${TMPDIR}
}
trap cleanup EXIT

cd ${TMPDIR} && $DUB fetch --cache=local bloom &
pid1=$!
sleep 0.5
cd ${TMPDIR} && $DUB fetch --cache=local bloom &
pid2=$!
wait $pid1
wait $pid2
[ -d ${TMPDIR}/.dub/packages/bloom* ]