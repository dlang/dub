#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd "$CURR_DIR"/ninja-generator

if ! $DUB generate ninja --compiler=$DC 2>&1; then
    die $LINENO 'dub generate ninja failed!'
fi

if [ ! -f build.ninja ]; then
    die $LINENO 'build.ninja was not generated!'
fi

if ! grep -q "rule dc" build.ninja; then
    die $LINENO 'build.ninja missing dc rule!'
fi

if ! grep -q "rule link" build.ninja; then
    die $LINENO 'build.ninja missing link rule!'
fi

if ! grep -q "rule regen" build.ninja; then
    die $LINENO 'build.ninja missing regen rule!'
fi

if ! grep -q "generator = 1" build.ninja; then
    die $LINENO 'build.ninja missing generator attribute on regen rule!'
fi

if ! grep -q "^build build.ninja: regen" build.ninja; then
    die $LINENO 'build.ninja missing self-regeneration build edge!'
fi

if ! grep "^build build.ninja: regen" build.ninja | grep -q "dub.json"; then
    die $LINENO 'build.ninja self-regeneration edge missing dub.json dependency!'
fi
rm -f build.ninja
