#!/bin/bash

set -v -e -o pipefail

if [ -z "$FRONTEND" -o "$FRONTEND" \> 2.067.z ]; then
    vibe_ver=$(jq -r '.versions | .["vibe-d"]' < dub.selections.json)
    dub fetch vibe-d --version=$vibe_ver # get optional dependency
    dub test --compiler=${DC} -c library-nonet
fi

if [ "$COVERAGE" = true ]; then
    # library-nonet fails to build with coverage (Issue 13742)
    dub test --compiler=${DC} -b unittest-cov
    ./build.sh -cov
else
    ./build.sh
fi
DUB=`pwd`/bin/dub DC=${DC} test/run-unittest.sh

if [ "$COVERAGE" = true ]; then
    wget https://codecov.io/bash -O codecov.sh
    bash codecov.sh
fi

# check for trailing whitespace (needs to be done only once per build)
if [ "$COVERAGE" = true ]; then
    find . -type f -name '*.d' -exec grep -Hn "[[:blank:]]$" {} \;
fi
