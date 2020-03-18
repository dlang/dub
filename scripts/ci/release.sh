#!/usr/bin/env bash

set -eux -o pipefail

# Get the directory root, which is two level ahead
ROOT_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd )"
cd ${ROOT_DIR}

VERSION=$(git describe --abbrev=0 --tags)
ARCH="${ARCH:-64}"
CUSTOM_FLAGS=()
unameOut="$(uname -s)"
case "$unameOut" in
    Linux*)
        OS=linux
        CUSTOM_FLAGS+=("-L--export-dynamic")
        ;;
    Darwin*)
        OS=osx
        CUSTOM_FLAGS+=("-L-dead_strip")
        ;;
    *) echo "Unknown OS: $unameOut"; exit 1
esac

if [[ $(basename "$DMD") =~ ldmd.* ]] ; then
    CUSTOM_FLAGS+=("-flto=full")
    # ld.gold is required on Linux
    if [ ${OS:-} == "linux" ] ; then
        CUSTOM_FLAGS+=("-linker=gold")
    fi
fi

case "$ARCH" in
    64) ARCH_SUFFIX="x86_64";;
    32) ARCH_SUFFIX="x86";;
    *) echo "Unknown ARCH: $ARCH"; exit 1
esac

archiveName="dub-$VERSION-$OS-$ARCH_SUFFIX.tar.gz"

echo "Building $archiveName"
DMD="$(command -v $DMD)" ./build.d -release -m$ARCH ${CUSTOM_FLAGS[@]}
tar cvfz "bin/$archiveName" -C bin dub
