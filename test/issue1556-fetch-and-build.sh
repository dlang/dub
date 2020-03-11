#!/usr/bin/env bash
DIR=$(dirname "${BASH_SOURCE[0]}")

. "$DIR"/common.sh

dub remove main-package --non-interactive --version=* 2>/dev/null || true
dub remove dependency-package --non-interactive --version=* 2>/dev/null || true


echo "Trying to fetch fs-sdl-dubpackage"
"$DUB" --cache=local fetch main-package --skip-registry=all --registry=file://"$DIR"/issue1556-fetch-and-build-pkgs

echo "Trying to build it (should fetch dependency-package)"
"$DUB" --cache=local build main-package --skip-registry=all --registry=file://"$DIR"/issue1556-fetch-and-build-pkgs

