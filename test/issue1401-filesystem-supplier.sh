#!/usr/bin/env bash
DIR=$(dirname "${BASH_SOURCE[0]}")

. "$DIR"/common.sh

dub remove fs-json-dubpackage --non-interactive 2>/dev/null || true
dub remove fs-sdl-dubpackage --non-interactive 2>/dev/null || true

echo "Trying to get fs-sdl-dubpackage (1.0.5)"
"$DUB" fetch fs-sdl-dubpackage --version=1.0.5 --skip-registry=all --registry=file://"$DIR"/issue1401-file-system-pkg-supplier

if ! dub remove fs-sdl-dubpackage --non-interactive --version=1.0.5 2>/dev/null; then
    die 'DUB did not install package from file system.'
fi

echo "Trying to get fs-sdl-dubpackage (latest)"
"$DUB" fetch fs-sdl-dubpackage --skip-registry=all --registry=file://"$DIR"/issue1401-file-system-pkg-supplier

if ! dub remove fs-sdl-dubpackage --non-interactive --version=1.0.6 2>/dev/null; then
    die 'DUB did not install latest package from file system.'
fi

echo "Trying to get fs-json-dubpackage (1.0.7)"
"$DUB" fetch fs-json-dubpackage --version=1.0.7 --skip-registry=all --registry=file://"$DIR"/issue1401-file-system-pkg-supplier

if ! dub remove fs-json-dubpackage --non-interactive --version=1.0.7 2>/dev/null; then
    die 'DUB did not install package from file system.'
fi
