#!/bin/bash

set -e -o pipefail

dub test --compiler=${DC} -c library-nonet

if [ "$COVERAGE" = true ]; then
    # library-nonet fails to build with coverage (Issue 13742)
    dub test --compiler=${DC} -b unittest-cov
    ./build.sh -cov
else
    ./build.sh
fi
DUB=`pwd`/bin/dub COMPILER=${DC} test/run-unittest.sh

if [ "$COVERAGE" = true ]; then
    dub fetch doveralls --version=~master
    dub run doveralls --compiler=${DC}
fi
