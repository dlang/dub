#!/bin/bash

set -e -o pipefail

TMPDIR=$(mktemp -d $(basename $0).XXXXXX)

function cleanup {
    rm -rf ${TMPDIR}
}
trap cleanup EXIT

cd ${TMPDIR} && $DUB fetch --cache=local bloom &
pid1=$!
cd ${TMPDIR} && $DUB fetch --cache=local bloom &
pid2=$!
wait $pid1
wait $pid2
if [ ! -d ${TMPDIR}/bloom* ]; then
    exit 1
fi
