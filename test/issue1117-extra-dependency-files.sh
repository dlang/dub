#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
fixture="$CURR_DIR/issue1117-extra-dependency-files"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -R "$fixture/source" "$fixture/dub.json" "$fixture/dependency.txt" "$work"
cd "$work"
export DUB_HOME="$work/dub-home"

check_inputs() {
	"$DUB" build
	actual=$(./test)
	[[ "$actual" == "$1" ]] || die $LINENO "Expected '$1', got '$actual'."
}

check_inputs ""
mkdir inputs
touch inputs/first.txt inputs/second.txt
check_inputs "firstsecond"

output=$("$DUB" build 2>&1)
grep -qF 'is up to date' <<< "$output" || die $LINENO 'Build was executed.' "$output"

for input in dependency.txt inputs/first.txt inputs/second.txt; do
	# The input must be strictly newer than the last build.
	sleep 1
	touch "$input"
	output=$("$DUB" build 2>&1)
	grep -qF 'building configuration' <<< "$output" || die $LINENO "Changing $input did not trigger a build." "$output"
done

rm inputs/first.txt
check_inputs "second"
rm inputs/second.txt
check_inputs ""
