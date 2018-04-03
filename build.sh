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

VERSION=$($DMD --version 2>/dev/null | sed -En 's|.*DMD.* v([[:digit:]\.]+).*|\1|p')
# workaround for link order issues with libcurl (phobos needs to come before curl)
if [[ $VERSION < 2.069.0 ]]; then
	# link against libcurl
	LIBS=`pkg-config --libs libcurl 2>/dev/null || echo "-lcurl"`

	# fix for modern GCC versions with --as-needed by default
	if [[ `$DMD --help | head -n1 | grep 'DMD\(32\|64\)'` ]]; then
		if [ `uname` = "Linux" ]; then
			LIBS="-l:libphobos2.a $LIBS"
		else
			LIBS="-lphobos2 $LIBS"
		fi
	elif [[ `$DMD --help | head -n1 | grep '^LDC '` ]]; then
		if [ `uname` = "SunOS" ]; then
			LIBS="-lnsl -lsocket -lphobos2-ldc $LIBS"
		else
			LIBS="-lphobos2-ldc $LIBS"
		fi
	fi

	# adjust linker flags for dmd command line
	LIBS=`echo "$LIBS" | sed 's/^-L/-L-L/; s/ -L/ -L-L/g; s/^-l/-L-l/; s/ -l/ -L-l/g'`
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
$DMD -ofbin/dub -g -O -w -version=DubUseCurl -Isource $* $LIBS @build-files.txt
bin/dub --version
echo DUB has been built as bin/dub.
echo
echo You may want to run
echo sudo ln -s $(pwd)/bin/dub /usr/local/bin
echo now.
