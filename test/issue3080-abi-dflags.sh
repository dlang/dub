#!/usr/bin/env bash

# Test for https://github.com/dlang/dub/issues/3080
# Verify that ABI-critical dflags from the root package are propagated
# to dependency compilations.

set -e

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd ${CURR_DIR}/issue3080-abi-dflags

# -checkaction is supported by DMD and LDC but not GDC
DC_BIN=$(basename "$DC")
if [ "$DC_BIN" = "gdc" ]; then
    echo "Skipping -checkaction propagation test for GDC."
    exit 0
fi

# Build with verbose output so we can see the compiler invocations
OUTPUT=$($DUB build --force --compiler=${DC} -v 2>&1)

# The root dub.json sets dflags: ["-checkaction=halt"].
# Verify that the dependency "dep" is also compiled with this flag.
# In verbose output, the dep compilation line looks like:
#   ldc2 ... dep/source/dep.d -checkaction=halt ...
# Count how many compiler invocation lines contain -checkaction=halt.
COUNT=$(echo "$OUTPUT" | grep -c '\-checkaction=halt' || true)
if [ "$COUNT" -ge 2 ]; then
    echo "PASS: -checkaction=halt propagated to dependency ($COUNT occurrences)."
else
    echo "FAIL: -checkaction=halt was not propagated to dependency (found $COUNT times)."
    echo "Verbose output:"
    echo "$OUTPUT"
    exit 1
fi
