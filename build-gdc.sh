#!/bin/sh
set -e

if [ "$GDC" = "" ]; then
        GDC=gdc
fi

# link against libcurl
LIBS=`pkg-config --libs libcurl 2>/dev/null || echo "-lcurl"`

# adjust linker flags for gdc command line
LIBS=`echo "$LIBS" | sed 's/^-L/-L-L/; s/ -L/ -L-L/g; s/^-l/-L-l/; s/ -l/ -L-l/g'`

echo Generating version file...
GITVER=$(git describe) || GITVER=unknown
echo "module dub.version_;" > source/dub/version_.d
echo "enum dubVersion = \"$GITVER\";" >> source/dub/version_.d

echo Running $GDC...
$GDC -obin/dub -lcurl -w -fversion=DubUseCurl -Isource $* $LIBS @build-files.txt
echo DUB has been built as bin/dub.
echo
echo You may want to run
echo sudo ln -s $(pwd)/bin/dub /usr/local/bin
echo now.
