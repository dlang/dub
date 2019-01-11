#!/usr/bin/env bash
# Build the Windows binaries under Linux
set -eux -o pipefail

BIN_NAME=dub

# Allow the script to be run from anywhere
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR

source setup-ldc-windows.sh

# Run LDC with cross-compilation
archiveName="$BIN_NAME-$VERSION-$OS-$ARCH_SUFFIX.zip"
echo "Building $archiveName"
mkdir -p bin
DC=ldmd2 DFLAGS="-release" ./build.sh

cd bin
mv "${BIN_NAME}" "${BIN_NAME}.exe"
zip "$archiveName" "${BIN_NAME}.exe"
