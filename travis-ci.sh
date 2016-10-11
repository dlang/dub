#!/bin/bash

set -v -e -o pipefail

if [ "$COVERAGE" = true ]; then
    # library-nonet fails to build with coverage (Issue 13742)
    dub test --compiler=${DC} -b unittest-cov
    ./build.sh -cov
else
    ./build.sh
fi

if [ -z "$FRONTEND" -o "$FRONTEND" \> 2.066.z ]; then
    vibe_ver=$(jq -r '.versions | .["vibe-d"]' < dub.selections.json)
    ./bin/dub fetch vibe-d --version=$vibe_ver # get optional dependency
    ./bin/dub test --compiler=${DC} -c library-nonet
fi

DUB=`pwd`/bin/dub DC=${DC} test/run-unittest.sh

if [ "$COVERAGE" = true ]; then
    ./bin/dub fetch doveralls
    ./bin/dub run doveralls --compiler=${DC}
fi
