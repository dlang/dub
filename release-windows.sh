#!/usr/bin/env bash
# Build the Windows binaries under Linux (requires wine)
set -eux -o pipefail
VERSION=$(git describe --abbrev=0 --tags)
OS=windows
if [ "${ARCH:-32}" == "64" ] ; then
	ARCH_SUFFIX="x86_64"
	export MFLAGS="-m64"
else
	ARCH_SUFFIX="x86"
	export MFLAGS="-m32"
fi


# Allow the script to be run from anywhere
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR

# Step 1: download the DMD binaries
if [ ! -d dmd2 ] ; then
	wget http://downloads.dlang.org/releases/2.x/2.080.0/dmd.2.080.0.windows.7z
	7z x dmd.2.080.0.windows.7z > /dev/null
fi

# Step 2: Run DMD via wineconsole
archiveName="dub-$VERSION-$OS-$ARCH_SUFFIX.zip"
echo "Building $archiveName"
mkdir -p bin
DC="$DIR/dmd2/windows/bin/dmd.exe" wine cmd /C build.cmd

cd bin
zip "$archiveName" dub.exe
