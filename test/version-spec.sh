#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

# When pipeing the dub output it is possible for head/tail to extract
# the output line before dub finished printing leading to dub
# receiving SIGPIPE. With pipefail this would fail the whole $()
# invocation leading to a ERROR result but, since $() invokes a
# subshell, the rest of the test still continue (and passes). The end
# result are 2 log lines, one for success and one for failure, for
# this single test file.
#
# The command that consistently fails for me is:
# $DUB list foo@'>0.1.0' | head -n 2 | tail -n 1
set +o pipefail

DUBPKGPATH=${DPATH+"$DPATH/dub/packages/dub"}
DUBPKGPATH=${DUBPKGPATH:-"$HOME/.dub/packages/dub"}

$DUB add-local "$CURR_DIR/version-spec/newfoo"
$DUB add-local "$CURR_DIR/version-spec/oldfoo"

[[ $($DUB describe foo | grep path | head -n 1) == *"/newfoo/"* ]]
[[ $($DUB describe foo@1.0.0 | grep path | head -n 1) == *"/newfoo/"* ]]
[[ $($DUB describe foo@0.1.0 | grep path | head -n 1) == *"/oldfoo/"* ]]

[[ $($DUB describe foo@'<1.0.0' | grep path | head -n 1) == *"/oldfoo/"* ]]
[[ $($DUB describe foo@'>0.1.0' | grep path | head -n 1) == *"/newfoo/"* ]]
[[ $($DUB describe foo@'>0.2.0' | grep path | head -n 1) == *"/newfoo/"* ]]
[[ $($DUB describe foo@'<=0.2.0' | grep path | head -n 1) == *"/oldfoo/"* ]]
[[ $($DUB describe foo@'*' | grep path | head -n 1) == *"/newfoo/"* ]]
[[ $($DUB describe foo@'>0.0.1 <2.0.0' | grep path | head -n 1) == *"/newfoo/"* ]]

[[ $($DUB test foo | tail -n +1 | head -n 1) == *"/newfoo/" ]]
[[ $($DUB test foo@1.0.0 | tail -n +1 | head -n 1) == *"/newfoo/" ]]
[[ $($DUB test foo@0.1.0 | tail -n +1 | head -n 1) == *"/oldfoo/" ]]

[[ $($DUB lint foo | tail -n 1) == *"/newfoo/" ]]
[[ $($DUB lint foo@1.0.0 | tail -n 1) == *"/newfoo/" ]]
[[ $($DUB lint foo@0.1.0 | tail -n 1) == *"/oldfoo/" ]]

[[ $($DUB generate cmake foo | tail -n +1 | head -n 1) == *"/newfoo/" ]]
[[ $($DUB generate cmake foo@1.0.0 | tail -n +1 | head -n 1) == *"/newfoo/" ]]
[[ $($DUB generate cmake foo@0.1.0 | tail -n +1 | head -n 1) == *"/oldfoo/" ]]

[[ $($DUB build -n foo | tail -n +1 | head -n 1) == *"/newfoo/" ]]
[[ $($DUB build -n foo@1.0.0 | tail -n +1 | head -n 1) == *"/newfoo/" ]]
[[ $($DUB build -n foo@0.1.0 | tail -n +1 | head -n 1) == *"/oldfoo/" ]]

[[ $($DUB run -n foo | tail -n 1) == 'new-foo' ]]
[[ $($DUB run -n foo@1.0.0 | tail -n 1) == 'new-foo' ]]
[[ $($DUB run -n foo@0.1.0 | tail -n 1) == 'old-foo' ]]

[[ $($DUB list foo | wc -l) == '4' ]]
[[ $($DUB list foo@0.1.0 | wc -l) == '3' ]]
[[ $($DUB list foo@'>0.1.0' | head -n 2 | tail -n 1) == *"/newfoo"* ]]

$DUB remove-local "$CURR_DIR/version-spec/newfoo"
$DUB remove-local "$CURR_DIR/version-spec/oldfoo"

$DUB fetch dub@1.9.0 && [ -d $DUBPKGPATH/1.9.0/dub ]
$DUB fetch dub=1.10.0 && [ -d $DUBPKGPATH/1.10.0/dub ]
$DUB remove dub@1.9.0
$DUB remove dub=1.10.0
if [ -d $DUBPKGPATH/1.9.0/dub ] || [ -d $DUBPKGPATH/1.10.0/dub ]; then
    die $LINENO 'Failed to remove specified versions'
fi
