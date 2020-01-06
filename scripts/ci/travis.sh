#!/bin/bash

set -v -e -o pipefail

vibe_ver=$(jq -r '.versions | .["vibe-d"]' < dub.selections.json)
dub fetch vibe-d --version=$vibe_ver # get optional dependency
dub test --compiler=${DC} -c library-nonet

export DMD="$(command -v $DMD)"

if [ "$FRONTEND" \> 2.087.z ]; then
    ./build.d -preview=dip1000 -w -g -debug
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
    ./build.d -cov

    wget https://codecov.io/bash -O codecov.sh
    bash codecov.sh
else
    ./build.d
    DUB=`pwd`/bin/dub DC=${DC} test/run-unittest.sh
fi

## Checks that only need to be done once per CI run
## Here the `COVERAGE` variable is abused for this purpose,
## as it's only defined once in the whole Travis matrix
if [ "$COVERAGE" = true ]; then
    # run tests with different compilers
    DUB=`pwd`/bin/dub DC=${DC} test/run-unittest.sh
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

    # check for trailing whitespace
    find . -type f -name '*.d' -exec grep -Hn "[[:blank:]]$" {} \;
    # check that the man page generation still works
    source $(~/dlang/install.sh dmd --activate)
    source $(~/dlang/install.sh dub --activate)
    dub --single -v scripts/man/gen_man.d
fi
