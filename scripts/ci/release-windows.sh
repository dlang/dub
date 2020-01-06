#!/usr/bin/env bash
# Build the Windows binaries under Linux
set -eux -o pipefail

BIN_NAME=dub

# Allow the script to be run from anywhere
DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd )"
cd $DIR

# Setup cross compiler
source scripts/ci/setup-ldc-windows.sh

# Run LDC with cross-compilation
archiveName="$BIN_NAME-$VERSION-$OS-$ARCH_SUFFIX.zip"
echo "Building $archiveName"
mkdir -p bin
DMD=ldmd2 ldc2 -run ./build.d -release ${LDC_XDFLAGS}

cd bin
zip "$archiveName" "${BIN_NAME}.exe"
