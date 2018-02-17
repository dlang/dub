#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

$DUB fetch dub --version=0.9.20 && [ -d $HOME/.dub/packages/dub-0.9.20/dub ]
$DUB fetch dub --version=0.9.21 && [ -d $HOME/.dub/packages/dub-0.9.21/dub ]
if $DUB remove dub --non-interactive 2>/dev/null; then
    die $LINENO 'Non-interactive remove should fail'
fi
echo 1 | $DUB remove dub | tr -d '\n' | grep --ignore-case 'select.*0\.9\.20.*0\.9\.21.*'
if [ -d $HOME/.dub/packages/dub-0.9.20/dub ]; then
    die $LINENO 'Failed to remove dub-0.9.20'
fi
$DUB fetch dub --version=0.9.20 && [ -d $HOME/.dub/packages/dub-0.9.20/dub ]
# EOF aborts remove
echo -xn '' | $DUB remove dub
if [ ! -d $HOME/.dub/packages/dub-0.9.20/dub ] || [ ! -d $HOME/.dub/packages/dub-0.9.21/dub ]; then
    die $LINENO 'Aborted dub still removed a package'
fi
# validates input
echo -e 'abc\n4\n-1\n3' | $DUB remove dub
if [ -d $HOME/.dub/packages/dub-0.9.20/dub ] || [ -d $HOME/.dub/packages/dub-0.9.21/dub ]; then
    die $LINENO 'Failed to remove all version of dub'
fi
$DUB fetch dub --version=0.9.20 && [ -d $HOME/.dub/packages/dub-0.9.20/dub ]
$DUB fetch dub --version=0.9.21 && [ -d $HOME/.dub/packages/dub-0.9.21/dub ]
# is non-interactive with --version=
$DUB remove dub --version=\*
if [ -d $HOME/.dub/packages/dub-0.9.20/dub ] || [ -d $HOME/.dub/packages/dub-0.9.21/dub ]; then
    die $LINENO 'Failed to non-interactively remove specified versions'
fi
