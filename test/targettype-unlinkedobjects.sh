#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/targettype-unlinkedobjects

"$DUB" build
ls obj > actual.txt

# no restriction by dub how the files in the output folder are named because
# the compiler might output other files than object files if wanted
# (e.g. asm or llvm ir)
# LDC currently names the files the full module name and DMD just the filename
if [[ $DC == *ldc* ]] || [[ $DC == *ldmd* ]]; then
	if ! diff expected.ldc.txt actual.txt; then
		die "didn't get expected object files"
	fi
elif [[ $DC == *dmd* ]]; then
	if ! diff expected.dmd.txt actual.txt; then
		die "didn't get expected object files"
	fi
# GDC unsupported
fi
