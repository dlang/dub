#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh

if [ -n "${PACKAGE_DIR-}" ]; then
	die $LINENO '$PACKAGE_DIR must not be set when running this test!'
fi

rm -f "$CURR_DIR/issue2229-sourcelib-packagedir/package.txt"

echo "main $CURR_DIR/issue2229-sourcelib-packagedir" > "$CURR_DIR/issue2229-sourcelib-packagedir/expected.txt"
echo "sourcelib $CURR_DIR/issue2229-sourcelib-packagedir/sourcelib" >> "$CURR_DIR/issue2229-sourcelib-packagedir/expected.txt"

if ! { $DUB build --force --root "$CURR_DIR/issue2229-sourcelib-packagedir" --skip-registry=all; }; then
	die $LINENO 'Failed to build package with sourceLibrary preBuildCommand.'
fi

if [ -s "$CURR_DIR/issue2229-sourcelib-packagedir/package.txt" ]; then
	diff "$CURR_DIR/issue2229-sourcelib-packagedir/package.txt" "$CURR_DIR/issue2229-sourcelib-packagedir/expected.txt" || die $LINENO 'Generated package.txt file differs from expected.txt'
	rm "$CURR_DIR/issue2229-sourcelib-packagedir/package.txt"
else
	die $LINENO 'Expected generated package.txt file is missing.'
fi
