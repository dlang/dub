#!/usr/bin/env bash

# sets up LDC for cross-compilation. Source this script, s.t. the new LDC is in PATH

LDC_VERSION="1.13.0"
ARCH=${ARCH:-32}
VERSION=$(git describe --abbrev=0 --tags)
OS=windows

# Step 0: install ldc
if [ ! -f install.sh ] ; then
	wget https://dlang.org/install.sh
fi
. $(bash ./install.sh -a "ldc-${LDC_VERSION}")

# for the install.sh script only
LDC_PATH="$(dirname $(dirname $(which ldc2)))"

# Step 1a: download the LDC x64 windows binaries
if [ "${ARCH}" == 64 ] && [ ! -d "ldc2-${LDC_VERSION}-windows-x64" ] ; then
	wget "https://github.com/ldc-developers/ldc/releases/download/v1.13.0/ldc2-${LDC_VERSION}-windows-x64.7z"
	7z x "ldc2-${LDC_VERSION}-windows-x64.7z" > /dev/null
	# Step 2a: Add LDC windows binaries to LDC Linux
	if [ ! -d "${LDC_PATH}/lib-win64" ] ; then
		cp -r ldc2-1.13.0-windows-x64/lib "${LDC_PATH}/lib-win64"
		cat >> "$LDC_PATH"/etc/ldc2.conf <<EOF
"x86_64-.*-windows-msvc":
{
	switches = [
		"-defaultlib=phobos2-ldc,druntime-ldc",
		"-link-defaultlib-shared=false",
	];
	lib-dirs = [
		"%%ldcbinarypath%%/../lib-win64",
	];
};
EOF
	fi
fi
# Step 1b: download the LDC x86 windows binaries
if [ "${ARCH}" == 32 ] && [ ! -d "ldc2-${LDC_VERSION}-windows-x86" ] ; then
	wget "https://github.com/ldc-developers/ldc/releases/download/v1.13.0/ldc2-${LDC_VERSION}-windows-x86.7z"
	7z x "ldc2-${LDC_VERSION}-windows-x86.7z" > /dev/null
	# Step 2b: Add LDC windows binaries to LDC Linux
	if [ ! -d "${LDC_PATH}/lib-win32" ] ; then
		cp -r ldc2-1.13.0-windows-x86/lib "${LDC_PATH}/lib-win32"
		cat >> "$LDC_PATH"/etc/ldc2.conf <<EOF
"i686-.*-windows-msvc":
{
	switches = [
		"-defaultlib=phobos2-ldc,druntime-ldc",
		"-link-defaultlib-shared=false",
	];
	lib-dirs = [
		"%%ldcbinarypath%%/../lib-win32",
	];
};
EOF
	fi
fi

# set suffices and compilation flags
if [ "$ARCH" == "64" ] ; then
	ARCH_SUFFIX="x86_64"
	export DFLAGS="-mtriple=x86_64-windows-msvc"
else
	ARCH_SUFFIX="x86"
	export DFLAGS="-mtriple=i686-windows-msvc"
fi

