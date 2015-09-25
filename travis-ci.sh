#!/bin/bash

set -e -o pipefail

if [ -z "$FRONTEND" -o "$FRONTEND" \> 2.064.2 ]; then
    dub fetch vibe-d --version=0.7.24 # get optional dependency
    dub test --compiler=${DC} -c library-nonet
fi

if [ "$COVERAGE" = true ]; then
    # library-nonet fails to build with coverage (Issue 13742)
    dub test --compiler=${DC} -b unittest-cov
    ./build.sh -cov
else
    ./build.sh
fi
DUB=`pwd`/bin/dub COMPILER=${DC} test/run-unittest.sh

if [ "$COVERAGE" = true ]; then
    dub fetch doveralls
    dub run doveralls --compiler=${DC}
fi
