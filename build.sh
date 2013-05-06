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

LIBS=`pkg-config --libs libcurl 2>/dev/null || echo "-lcurl"`
LIBS=`echo "$LIBS" | sed 's/^-L/-L-L/; s/ -L/ -L-L/g; s/^-l/-L-l/; s/ -l/ -L-l/g'`

# HACK to work around (r)dmd placing -lcurl before the object files - which is wrong if --as-needed is used
# On newer Ubuntu versions this is the default, though
if [ -f /etc/lsb-release ]; then
	lsb_release -i | grep "Ubuntu" 2> /dev/null && LIBS="-L--no-as-needed $LIBS"
fi

echo Running $DC...
$DC -ofbin/dub -g -debug -w -property -Isource $* $LIBS @build-files.txt
echo DUB has been built as bin/dub.
echo
echo You may want to run
echo sudo ln -s $(pwd)/bin/dub /usr/local/bin
echo now.
