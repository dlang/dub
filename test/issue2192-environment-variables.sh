#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh

if [ -n "${DUB_PACKAGE-}" ]; then
  die $LINENO '$DUB_PACKAGE must not be set when running this test!'
fi

if ! { $DUB build --force --root "$CURR_DIR/issue2192-environment-variables" --skip-registry=all; }; then
	die $LINENO 'Failed to build package with built-in environment variables.'
fi

if [ -s "$CURR_DIR/issue2192-environment-variables/package.txt" ]; then
	rm "$CURR_DIR/issue2192-environment-variables/package.txt"
else
	die $LINENO 'Expected generated package.txt file is missing.'
fi

OUTPUT=$($DUB describe --root "$CURR_DIR/issue2192-environment-variables" --skip-registry=all --data=pre-build-commands --data-list)
if [ "$OUTPUT" != "echo 'issue2192-environment-variables' > package.txt" ]; then
	die $LINENO 'describe did not contain subtituted values or the correct package name'
fi
