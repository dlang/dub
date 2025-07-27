#!/bin/bash

set -v -e -o pipefail

testLibraryNonet=1
if [[ ${DC} =~ gdc|gdmd ]]; then
    # ICE with gdc-14
    testLibraryNonet=
fi

if [[ ${testLibraryNonet} ]]; then
    vibe_ver=$(jq -r '.versions | .["vibe-d"]' < dub.selections.json)
    dub fetch vibe-d@$vibe_ver # get optional dependency
    dub test --compiler=${DC} -c library-nonet --build=unittest
fi

export DMD="$(command -v $DMD)"

"${DMD}" -run build.d -preview=in -w -g -debug

if [[ ${testLibraryNoNet} ]]; then
    dub test --compiler=${DC} -b unittest-cov
fi

if [ "$COVERAGE" = true ]; then
    # library-nonet fails to build with coverage (Issue 13742)
    "${DMD}" -run build.d -cov
else
    "${DMD}" -run build.d
fi

# force the creation of the coverage dir
bin/dub --version

# let the runner add the needed flags, in the case of gdmd
unset DFLAGS
DC=${DMD} dub run --root test/run_unittest -- -v
