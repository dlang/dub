#!/bin/bash

set -v -e -o pipefail

source ~/dlang/*/activate # activate host compiler

if [ -z "$FRONTEND" -o "$FRONTEND" \> 2.072.z ]; then
    vibe_ver=$(jq -r '.versions | .["vibe-d"]' < dub.selections.json)
    dub fetch vibe-d --version=$vibe_ver # get optional dependency
    dub test --compiler=${DC} -c library-nonet
fi

function clean() {
    # Hard reset of the DUB local folder is necessary as some tests
    # currently don't properly clean themselves
    rm -rf ~/.dub
    git clean -dxf -- test
}

if [ "$COVERAGE" = true ]; then
    # library-nonet fails to build with coverage (Issue 13742)
    dub test --compiler=${DC} -b unittest-cov
    ./build.sh -cov

    # run tests with different compilers
    DUB=`pwd`/bin/dub DC=${DC} test/run-unittest.sh
    deactivate
    clean

    export FRONTEND=2.077
    source $(~/dlang/install.sh ldc-1.7.0 --activate)
    DUB=`pwd`/bin/dub DC=${DC} test/run-unittest.sh
    deactivate
    clean

    export FRONTEND=2.068
    source $(~/dlang/install.sh gdc-4.8.5 --activate)
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
