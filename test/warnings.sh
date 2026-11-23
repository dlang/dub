#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

echo "Regular run"
$DUB run --force --root="$CURR_DIR/warnings" --config=executable 2>&1 >/dev/null
echo "Expect bar() to be called"
$DUB run --force --root="$CURR_DIR/warnings" --config=executable-d 2>&1 | grep 'called bar' -c

echo "Should have no deprecation message"
$DUB run --force --root="$CURR_DIR/warnings" --config=executable-d --build=no-d 2>&1 | { ! grep -F 'deprecated' -c; }
echo "Deprecation should cause error"
! $DUB run --force --root="$CURR_DIR/warnings" --config=executable-d --build=de 2>&1 >/dev/null
echo "Deprecation should cause warning, thus an error because of default warning-as-error behavior"
! $DUB run --force --root="$CURR_DIR/warnings" --config=executable-d --build=dw 2>&1 >/dev/null
echo "Deprecation as error should cause error, even if warnings are allowed"
! $DUB run --force --root="$CURR_DIR/warnings" --config=executable-d --build=de-allow 2>&1 >/dev/null
echo "Deprecation as warning should be fine if warnings are allowed"
$DUB run --force --root="$CURR_DIR/warnings" --config=executable-d --build=dw-allow 2>&1 | grep -F 'deprecated' -c
echo "Allowing warnings should leave deprecations untouched"
$DUB run --force --root="$CURR_DIR/warnings" --config=executable-d --build=allow 2>&1 | grep -F 'deprecated' -c

echo "Expecting warning output with deprecationErrors still working as usual"
$DUB run --force --root="$CURR_DIR/warnings" --config=executable-w --build=de-allow 2>&1 | grep -i 'warning' -c
echo "Expecting warning output with deprecationWarnings still working as usual"
$DUB run --force --root="$CURR_DIR/warnings" --config=executable-w --build=dw-allow 2>&1 | grep -i 'warning' -c
echo "Expecting warning output with allowed warnings working as usual"
$DUB run --force --root="$CURR_DIR/warnings" --config=executable-w --build=allow 2>&1 | grep -i 'warning' -c
echo "Make sure the deprecated function didn't somehow get in"
$DUB run --force --root="$CURR_DIR/warnings" --config=executable-w --build=allow 2>&1 | { ! grep 'called bar' -c; }

echo "Warning should break build, deprecation should still be in"
! $DUB run --force --root="$CURR_DIR/warnings" --config=executable-dw --build=no-d 2>&1 | grep -F 'deprecated' -c
echo "Warning + deprecation as error should break build"
! $DUB run --force --root="$CURR_DIR/warnings" --config=executable-dw --build=de 2>&1 | grep -F 'deprecated' -c
echo "Warning + deprecation as warning should break build"
! $DUB run --force --root="$CURR_DIR/warnings" --config=executable-dw --build=dw 2>&1 | grep -F 'deprecated' -c
echo "deprecation as error with allowed warnings should break build"
! $DUB run --force --root="$CURR_DIR/warnings" --config=executable-dw --build=de-allow 2>&1 >/dev/null
echo "deprecation as warnings with allowed warnings should work fine"
$DUB run --force --root="$CURR_DIR/warnings" --config=executable-dw --build=dw-allow 2>&1 | grep -F 'deprecated' -c
echo "allowed warnings should work fine"
$DUB run --force --root="$CURR_DIR/warnings" --config=executable-dw --build=allow 2>&1 | grep -F 'deprecated' -c
