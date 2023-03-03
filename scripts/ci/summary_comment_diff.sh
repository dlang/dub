#!/usr/bin/env bash

set -u

EMPTY=1

ADDED=$(diff --new-line-format='%L' --old-line-format='' --unchanged-line-format='' "$1" "$2")
REMOVED=$(diff --new-line-format='' --old-line-format='%L' --unchanged-line-format='' "$1" "$2")
TOTAL=$(cat "$2")

STATS_OLD=$(grep -E '^STAT:' "$1" | sed -E 's/^STAT://')
STATS_NEW=$(grep -E '^STAT:' "$2" | sed -E 's/^STAT://')

STATS_DIFFED=$(diff --new-line-format='+%L' --old-line-format='-%L' --unchanged-line-format=' %L' <(echo "$STATS_OLD") <(echo "$STATS_NEW"))

ADDED_DEPRECATIONS=$(grep -Pi '\b(deprecation|deprecated)\b' <<< "$ADDED")
REMOVED_DEPRECATIONS=$(grep -Pi '\b(deprecation|deprecated)\b' <<< "$REMOVED")
ADDED_WARNINGS=$(grep -Pi '\b(warn|warning)\b' <<< "$ADDED")
REMOVED_WARNINGS=$(grep -Pi '\b(warn|warning)\b' <<< "$REMOVED")

DEPRECATION_COUNT=$(grep -Pi '\b(deprecation|deprecated)\b' <<< "$TOTAL" | wc -l)
WARNING_COUNT=$(grep -Pi '\b(warn|warning)\b' <<< "$TOTAL" | wc -l)

if [ -z "$ADDED_DEPRECATIONS" ]; then
	# no new deprecations
	true
else
	echo "⚠️ This PR introduces new deprecations:"
	echo
	echo '```'
	echo "$ADDED_DEPRECATIONS"
	echo '```'
	echo
	EMPTY=0
fi

if [ -z "$ADDED_WARNINGS" ]; then
	# no new deprecations
	true
else
	echo "⚠️ This PR introduces new warnings:"
	echo
	echo '```'
	echo "$ADDED_WARNINGS"
	echo '```'
	echo
	EMPTY=0
fi

if grep "BUILD FAILED" <<< "$TOTAL"; then
	echo '❌ Basic `dub build` failed! Please check your changes again.'
	echo
else
	if [ -z "$REMOVED_DEPRECATIONS" ]; then
		# no removed deprecations
		true
	else
		echo "✅ This PR fixes following deprecations:"
		echo
		echo '```'
		echo "$REMOVED_DEPRECATIONS"
		echo '```'
		echo
		EMPTY=0
	fi

	if [ -z "$REMOVED_WARNINGS" ]; then
		# no removed warnings
		true
	else
		echo "✅ This PR fixes following warnings:"
		echo
		echo '```'
		echo "$REMOVED_WARNINGS"
		echo '```'
		echo
		EMPTY=0
	fi

	if [ $EMPTY == 1 ]; then
		echo "✅ PR OK, no changes in deprecations or warnings"
		echo
	fi

	echo "Total deprecations: $DEPRECATION_COUNT"
	echo
	echo "Total warnings: $WARNING_COUNT"
	echo
fi

if [ -z "$STATS_DIFFED" ]; then
	# no statistics?
	true
else
	echo "Build statistics:"
	echo
	echo '```diff'
	echo "$STATS_DIFFED"
	echo '```'
	echo
fi

echo '<details>'
echo
echo '<summary>Full build output</summary>'
echo
echo '```'
echo "$TOTAL"
echo '```'
echo
echo '</details>'
