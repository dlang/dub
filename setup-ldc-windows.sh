#!/usr/bin/env bash

# sets up LDC for cross-compilation. Source this script, s.t. the new LDC is in PATH

# Make sure this version matches the version of LDC2 used in .travis.yml,
# otherwise the compiler and the lib used might mismatch.
LDC_VERSION="1.18.0"
ARCH=${ARCH:-32}
VERSION=$(git describe --abbrev=0 --tags)
OS=windows

# LDC should already be installed (see .travis.yml)
# However, we need the libraries, so download them
# We can't use the downloaded ldc2 itself, because obviously it's for Windows

if [ "${ARCH}" == 64 ]; then
	ARCH_SUFFIX='x86_64'
	ZIP_ARCH_SUFFIX='x64'
else
	ARCH_SUFFIX='i686'
	ZIP_ARCH_SUFFIX='x86'
fi

LDC_DIR_PATH="$(pwd)/ldc2-${LDC_VERSION}-windows-${ZIP_ARCH_SUFFIX}"
LDC_XDFLAGS="-conf=${LDC_DIR_PATH}/etc/ldc2.conf -mtriple=${ARCH_SUFFIX}-pc-windows-msvc"

# Step 1: download the LDC Windows release
# Check if the user already have it (e.g. building locally)
if [ ! -d ${LDC_DIR_PATH} ]; then
    if [ ! -d "ldc2-${LDC_VERSION}-windows-${ZIP_ARCH_SUFFIX}.7z" ]; then
        wget "https://github.com/ldc-developers/ldc/releases/download/v${LDC_VERSION}/ldc2-${LDC_VERSION}-windows-${ZIP_ARCH_SUFFIX}.7z"
    fi
    7z x "ldc2-${LDC_VERSION}-windows-${ZIP_ARCH_SUFFIX}.7z" > /dev/null
fi

# Step 2: Generate a config file with the proper path
cat > ${LDC_DIR_PATH}/etc/ldc2.conf <<EOF
default:
{
	switches = [
		"-defaultlib=phobos2-ldc,druntime-ldc",
		"-link-defaultlib-shared=false",
	];
    post-switches = [
        "-I${LDC_DIR_PATH}/import",
    ];
	lib-dirs = [
		"${LDC_DIR_PATH}/lib/",
		"${LDC_DIR_PATH}/lib/mingw/",
	];
};
EOF
