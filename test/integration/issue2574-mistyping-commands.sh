#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

$DUB upfrade 2>&1 >/dev/null && die $LINENO '"dub upfrade" should not succeed'

if [ "$($DUB upfrade 2>&1 | grep -Fc "Unknown command: upfrade")" != "1" ]; then
	die $LINENO 'Missing Unknown command line'
fi

if [ "$($DUB upfrade 2>&1 | grep -Fc "Did you mean 'upgrade'?")" != "1" ]; then
	die $LINENO 'Missing upgrade suggestion'
fi

if [ "$($DUB upfrade 2>&1 | grep -Fc "build")" != "0" ]; then
	die $LINENO 'Did not expect to see build as a suggestion and did not want a full list of commands'
fi
