#!/usr/bin/env bash
set -e

echo "@@@@@ WARNING @@@@@"
echo "@ This script is DEPRECATED. Use build.d directly instead @"
echo "@@@@@@@@@@@@@@@@@@@@"

if [ "$DMD" = "" ]; then
	if [ ! "$DC" = "" ]; then # backwards compatibility with DC
		DMD=$DC
	else
		command -v gdmd >/dev/null 2>&1 && DMD=gdmd || true
		command -v ldmd2 >/dev/null 2>&1 && DMD=ldmd2 || true
		command -v dmd >/dev/null 2>&1 && DMD=dmd || true
	fi
fi

if [ "$DMD" = "" ]; then
	echo >&2 "Failed to detect D compiler. Use DMD=... to set a dmd compatible binary manually."
	exit 1
fi

$DMD -run build.d $*
