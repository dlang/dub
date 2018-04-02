#!/bin/bash

set -v -e -o pipefail

VERSION=$(git describe --abbrev=0 --tags)
ARCH="${ARCH:-64}"
CUSTOM_FLAGS=""

unameOut="$(uname -s)"
case "$unameOut" in
    Linux*)
        OS=linux
        CUSTOM_FLAGS="-L--export-dynamic"
        ;;
    Darwin*)
        OS=osx
        ;;
    *) echo "Unknown OS: $unameOut"; exit 1
esac

case "$ARCH" in
    64) ARCH_SUFFIX="x86_64";;
    32) ARCH_SUFFIX="x86";;
    *) echo "Unknown ARCH: $ARCH"; exit 1
esac

archiveName="dub-$VERSION-$OS-$ARCH_SUFFIX.tar.gz"

echo "Building $archiveName"
DFLAGS="-release -m$ARCH ${CUSTOM_FLAGS}" DMD="$(command -v $DMD)" ./build.sh
tar cvfz "bin/$archiveName" -C bin dub
