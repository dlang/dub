#!/usr/bin/env bash
set -e

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

if [ "$GITVER" = "" ]; then
  GITVER=$(git describe) || echo "Could not determine a version with git."
fi
if [ "$GITVER" != "" ]; then
	echo Generating version file...
	echo "module dub.version_;" > source/dub/version_.d
	echo "enum dubVersion = \"$GITVER\";" >> source/dub/version_.d
else
	echo Using existing version file.
fi

# For OSX compatibility >= 10.8
MACOSX_DEPLOYMENT_TARGET=10.8

echo Running $DMD...
$DMD -ofbin/dub -g -O -w -version=DubUseCurl -version=DubApplication -Isource $* @build-files.txt
bin/dub --version
echo DUB has been built as bin/dub.
echo
echo You may want to run
echo sudo ln -s $(pwd)/bin/dub /usr/local/bin
echo now.
