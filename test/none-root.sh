#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

# https://github.com/dlang/dub/issues/3167
# A root package of target type "none" has its build settings (including
# targetName) reset by the generator. `dub describe` and `dub run` used to
# trigger a "No target name set." assertion in `Compiler.getTargetFileName`.

cd "$CURR_DIR"/none-root

if ! output=$($DUB describe --compiler=$DC); then
    die $LINENO 'dub describe failed for a root package with target type "none"'
fi

if ! grep -q '"rootPackage": "none-root:lib"' <<< "$output"; then
    die $LINENO 'dub describe did not produce a target description for the dependency'
fi

# With assertions off, dub describe would formerly append an empty targetName to a directory
if grep -qE '"cacheArtifactPath": "[^"]*(/|\\)"' <<< "$output"; then
    die $LINENO 'dub describe reported a cache artifact path without a file name'
fi

# There is nothing to run, but dub should fail gracefully
if output=$($DUB run --compiler=$DC 2>&1); then
    die $LINENO 'dub run succeeded for a root package with target type "none"'
fi

if grep -q 'AssertError' <<< "$output"; then
    die $LINENO 'dub run triggered an assertion for a root package with target type "none"'
fi
