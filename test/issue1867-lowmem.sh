#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh
DIR=$(dirname "${BASH_SOURCE[0]}")

if ! { ${DUB} build --root ${DIR}/issue1867-lowmem -v -f 2>&1 || true; } | grep -cF " -lowmem " > /dev/null; then
    die $LINENO 'DUB build with lowmem did not find -lowmem option.'
fi

if ! { ${DUB} test --root ${DIR}/issue1867-lowmem -v -f 2>&1 || true; } | grep -cF " -lowmem " > /dev/null; then
    die $LINENO 'DUB test with lowmem did not find -lowmem option.'
fi

if ! { ${DUB} run --root ${DIR}/issue1867-lowmem -v -f 2>&1 || true; } | grep -cF " -lowmem " > /dev/null; then
    die $LINENO 'DUB test with lowmem did not find -lowmem option.'
fi

if ! { ${DUB} describe --root ${DIR}/issue1867-lowmem --data=options --data-list --verror 2>&1 || true; } | grep -cF "lowmem" > /dev/null; then
    die $LINENO 'DUB describe --data=options --data-list with lowmem did not find lowmem option.'
fi
