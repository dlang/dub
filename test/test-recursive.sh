#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

should_contain () {
	for c in ${@:2}; do
		if ! { echo $1; } | grep "$c"; then
			die $LINENO "$c was not tested."
			exit 1
		fi
	done
}

should_not_contain () {
	for c in ${@:2}; do
		if   { echo $1; } | grep "$c"; then
			die $LINENO "Unexpected line '$c' was detected."
			exit 1
		fi
	done
}

should_contain     "$($DUB test -r --root=$(dirname "${BASH_SOURCE[0]}")/test-recursive 2>&1)" "rootPackage" "libraryA" "libraryB" "libraryC"
should_contain     "$($DUB test    --root=$(dirname "${BASH_SOURCE[0]}")/test-recursive 2>&1)" "rootPackage"
should_not_contain "$($DUB test    --root=$(dirname "${BASH_SOURCE[0]}")/test-recursive 2>&1)" "libraryA" "libraryB" "libraryC"
