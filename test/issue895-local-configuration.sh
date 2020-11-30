#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh

if [ -e /var/lib/dub/settings.json ]; then
	die $LINENO 'Found existing system wide DUB configuration. Aborting.'
fi

if [ -e ~/.dub/settings.json ]; then
	die $LINENO 'Found existing user wide DUB configuration. Aborting.'
fi

cd ${CURR_DIR}
mkdir -p ../etc/dub
echo "{\"defaultCompiler\": \"foo\"}" > ../etc/dub/settings.json
echo "Empty file named foo." > ../bin/foo

function cleanup {
    rm -r ../etc
}

trap cleanup EXIT

unset DC

if ! { ${DUB} describe --single issue103-single-file-package.d 2>&1 || true; } | grep -cF "Unknown compiler: $(dirname $CURR_DIR)/bin/foo"; then
	rm ../bin/foo
	die $LINENO 'DUB did not find the local configuration with an adjacent compiler.'
fi

echo "{\"defaultCompiler\": \"$CURR_DIR/foo\"}" > ../etc/dub/settings.json
mv ../bin/foo $CURR_DIR

if ! { ${DUB} describe --single issue103-single-file-package.d 2>&1 || true; } | grep -cF "Unknown compiler: $CURR_DIR/foo"; then
	rm $CURR_DIR/foo
	die $LINENO 'DUB did not find a locally-configured compiler with an absolute path.'
fi

echo "{\"defaultCompiler\": \"~/.dub/foo\"}" > ../etc/dub/settings.json
mv $CURR_DIR/foo ~/.dub/

if ! { ${DUB} describe --single issue103-single-file-package.d 2>&1 || true; } | grep -cF "Unknown compiler: "; then
	rm ~/.dub/foo
	die $LINENO 'DUB did not find a locally-configured compiler with a tilde-prefixed path.'
fi

echo "{\"defaultCompiler\": \"\$DUB_BINARY_PATH/../foo\"}" > ../etc/dub/settings.json
mv ~/.dub/foo ..

if ! { ${DUB} describe --single issue103-single-file-package.d 2>&1 || true; } | grep -cF "Unknown compiler: $(dirname $CURR_DIR)/bin/../foo"; then
	rm ../foo
	die $LINENO 'DUB did not find a locally-configured compiler with a DUB-relative path.'
fi

echo "{\"defaultCompiler\": \"../foo\"}" > ../etc/dub/settings.json

if ! { ${DUB} describe --single issue103-single-file-package.d 2>&1 || true; } | grep -cF "defaultCompiler specified in a DUB config file cannot use an unqualified relative path"; then
	rm ../foo
	die $LINENO 'DUB did not error properly for a locally-configured compiler with a relative path.'
fi

rm ../etc/dub/settings.json
echo "Empty file named ldc2." > ../bin/ldc2

if ! { ${DUB} describe --single issue103-single-file-package.d 2>&1 || true; } | grep -cF "Failed to invoke the compiler $(dirname $CURR_DIR)/bin/ldc2 to determine the build platform"; then
	rm ../bin/ldc2
	die $LINENO 'DUB did not find ldc2 adjacent to it.'
fi

echo "{\"defaultCompiler\": \"foo\"}" > ../etc/dub/settings.json
rm ../bin/ldc2
export PATH=$(dirname $CURR_DIR)${PATH:+:$PATH}

if ! { ${DUB} describe --single issue103-single-file-package.d 2>&1 || true; } | grep -cF "Unknown compiler: foo"; then
	rm ../foo
	die $LINENO 'DUB did not find a locally-configured compiler in its PATH.'
fi

rm ../foo
