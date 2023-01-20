#!/bin/bash

set -v -e -o pipefail

vibe_ver=$(jq -r '.versions | .["vibe-d"]' < dub.selections.json)
dub fetch vibe-d@$vibe_ver # get optional dependency
dub test --compiler=${DC} -c library-nonet

export DMD="$(command -v $DMD)"

if [ "$FRONTEND" \> 2.087.z ]; then
    ./build.d -preview=dip1000 -preview=in -w -g -debug
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
    DUB=`pwd`/bin/dub DC=${DC} dub --single ./test/run-unittest.d
    DUB=`pwd`/bin/dub DC=${DC} test/run-unittest.sh
fi

## Checks that only need to be done once per CI run
## We choose to run them only on ldc-latest
if [[ "$CI_DC" == "ldc-latest" && "$CI_OS" =~ ^ubuntu.* ]]; then
    # check for trailing whitespace
    find . -type f -name '*.d' -exec grep -Hn "[[:blank:]]$" {} \;
    # check that the man page generation still works
    dub --single -v scripts/man/gen_man.d
fi
