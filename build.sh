#!/bin/sh
set -e

if [ "$DC" = "" ]; then
	command -v gdmd >/dev/null 2>&1 && DC=gdmd || true
	command -v ldmd2 >/dev/null 2>&1 && DC=ldmd2 || true
	command -v dmd >/dev/null 2>&1 && DC=dmd || true
fi

if [ "$DC" = "" ]; then
	echo >&2 "Failed to detect D compiler. Use DC=... to set a dmd compatible binary manually."
	exit 1
fi

# link against libcurl
LIBS=`pkg-config --libs libcurl 2>/dev/null || echo "-lcurl"`

# adjust linker flags for dmd command line
LIBS=`echo "$LIBS" | sed 's/^-L/-L-L/; s/ -L/ -L-L/g; s/^-l/-L-l/; s/ -l/ -L-l/g'`

echo Generating version file...
GITVER=$(git describe) || GITVER=unknown
echo "module dub.version_;" > source/dub/version_.d
echo "enum dubVersion = \"$GITVER\";" >> source/dub/version_.d
echo "enum initialCompilerBinary = \"$DC\";" >> source/dub/version_.d


echo Running $DC...
$DC -ofbin/dub -w -version=DubUseCurl -Isource $* $LIBS @build-files.txt
echo DUB has been built as bin/dub.
echo
echo You may want to run
echo sudo ln -s $(pwd)/bin/dub /usr/local/bin
echo now.
