#!/usr/bin/env bash

set -euo pipefail

# Ensure DC is available
export DC="$(command -v ${DC:-})"
command -v "$DC" >/dev/null || \
  { echo >&2 '[ERROR] "$DC" should be available'; exit 1; }

# Ensure that the globally installed 'dub' is not implicitly available for the testsuite.
#
# 1/3 Rename it to "$HOST_DUB" and hide it:
export HOST_DUB
HOST_DUB="$(command -v dub)" ||
  { echo >&2 "[ERROR] 'dub' should be available"; exit 1; }
unset DUB
hash -p /dev/null/dub dub

# 2/3 Verify that both 'dub' and "$DUB" are not available:
dub > /dev/null 2>&1 || command -v "${DUB:-}" >/dev/null && \
  { echo >&2 "[ERROR] 'dub' shouldn't be available"; exit 1; }
# 3/3 Verify that "$HOST_DUB" *is* available:
command -v "$HOST_DUB" >/dev/null || \
  { echo >&2 '[ERROR] "$HOST_DUB" should be available'; exit 1; }

echo "| Toolchain info: |"
# Use intermediate file, to prevent "LLVM ERROR: IO failure on output stream: Broken pipe"
# with: `ldc2 --version | head -n1` :O
tmpfile=$(mktemp ./dub-ci-toolchain-info.XXXXXXXXXX)
echo '---'
echo -n '"$DC": ' && command -v "$DC" && "$DC" --version > "$tmpfile" && cat "$tmpfile" | head -n1
echo '---'
echo -n '"$HOST_DUB": ' && command -v "$HOST_DUB" && "$HOST_DUB" --version > "$tmpfile" && cat "$tmpfile" | head -n1
echo '---'
rm "$tmpfile"

# Enable more verbose script execution:
set -v

# Configuration `library-nonet` can be built without vibe-d, (it's an optional
# dependency), but we fetch it as we want to test building with it included:
vibe_ver=$(jq -r '.versions | .["vibe-d"]' < dub.selections.json)
"$HOST_DUB" fetch vibe-d --version=$vibe_ver

# Build configuration `library-nonet`:
"$HOST_DUB" test --compiler=${DC} -c library-nonet

if [ "$FRONTEND" \> 2.087.z ]; then
    ./build.d -preview=dip1000 -w -g -debug
fi

function clean() {
    # Hard reset of the DUB local folder is necessary as some tests
    # currently don't properly clean themselves
    rm -rf ~/.dub
    git clean -dxf -- test
}

if [ "${COVERAGE:-}" = true ]; then
    # library-nonet fails to build with coverage (Issue 13742)
    "$HOST_DUB" test --compiler=${DC} -b unittest-cov
    ./build.d -cov

    wget https://codecov.io/bash -O codecov.sh
    bash codecov.sh
else
    ./build.d
    DUB=`pwd`/bin/dub DC=${DC} dub --single ./test/run-unittest.d
    DUB=`pwd`/bin/dub DC=${DC} test/run-unittest.sh
fi

## Checks that only need to be done once per CI run
## Here the `COVERAGE` variable is abused for this purpose,
## as it's only defined once in the whole Travis matrix
if [ "${COVERAGE:-}" = true ]; then
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
    "$DUB" --single -v scripts/man/gen_man.d
fi
