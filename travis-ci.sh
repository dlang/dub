#!/bin/bash

set -v -e -o pipefail

source ~/dlang/*/activate # activate host compiler

if [ -z "$FRONTEND" -o "$FRONTEND" \> 2.071.z ]; then
    vibe_ver=$(jq -r '.versions | .["vibe-d"]' < dub.selections.json)
    dub fetch vibe-d --version=$vibe_ver # get optional dependency
    dub test --compiler=${DC} -c library-nonet
fi

if [ "$COVERAGE" = true ]; then
    # library-nonet fails to build with coverage (Issue 13742)
    dub test --compiler=${DC} -b unittest-cov
    ./build.sh -cov

    # run tests with different compilers
    DUB=`pwd`/bin/dub DC=${DC} test/run-unittest.sh
    deactivate
    git clean -dxf -- test
    source $(~/dlang/install.sh ldc --activate)
    DUB=`pwd`/bin/dub DC=${DC} test/run-unittest.sh
    deactivate
    git clean -dxf -- test
    source $(~/dlang/install.sh gdc --activate)
    DUB=`pwd`/bin/dub DC=${DC} test/run-unittest.sh
    deactivate
else
    ./build.sh
    DUB=`pwd`/bin/dub DC=${DC} test/run-unittest.sh
fi

if [ "$COVERAGE" = true ]; then
    wget https://codecov.io/bash -O codecov.sh
    bash codecov.sh
fi

# check for trailing whitespace (needs to be done only once per build)
if [ "$COVERAGE" = true ]; then
    find . -type f -name '*.d' -exec grep -Hn "[[:blank:]]$" {} \;
fi

# check that the man page generation still works (only once)
if [ "$COVERAGE" = true ]; then
    source $(~/dlang/install.sh dmd --activate)
    dub --single -v scripts/man/gen_man.d
fi
