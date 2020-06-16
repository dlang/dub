#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

# This test messes with the user's package directory
# Hence it's a pretty bad test, but we need it.
# Ideally, we should not have this run by default / run it in a container.
# In the meantime, in order to make it pass on developer's machines,
# we need to nuke every `dub` version in the user cache...
$DUB remove dub -n --version=* || true

$DUB fetch dub --version=1.9.0 && [ -d $HOME/.dub/packages/dub-1.9.0/dub ]
$DUB fetch dub --version=1.10.0 && [ -d $HOME/.dub/packages/dub-1.10.0/dub ]
if $DUB remove dub --non-interactive 2>/dev/null; then
    die $LINENO 'Non-interactive remove should fail'
fi
echo 1 | $DUB remove dub | tr -d '\n' | grep --ignore-case 'select.*1\.9\.0.*1\.10\.0.*'
if [ -d $HOME/.dub/packages/dub-1.9.0/dub ]; then
    die $LINENO 'Failed to remove dub-1.9.0'
fi
$DUB fetch dub --version=1.9.0 && [ -d $HOME/.dub/packages/dub-1.9.0/dub ]
# EOF aborts remove
echo -xn '' | $DUB remove dub
if [ ! -d $HOME/.dub/packages/dub-1.9.0/dub ] || [ ! -d $HOME/.dub/packages/dub-1.10.0/dub ]; then
    die $LINENO 'Aborted dub still removed a package'
fi
# validates input
echo -e 'abc\n4\n-1\n3' | $DUB remove dub
if [ -d $HOME/.dub/packages/dub-1.9.0/dub ] || [ -d $HOME/.dub/packages/dub-1.10.0/dub ]; then
    die $LINENO 'Failed to remove all version of dub'
fi
$DUB fetch dub --version=1.9.0 && [ -d $HOME/.dub/packages/dub-1.9.0/dub ]
$DUB fetch dub@1.10.0 && [ -d $HOME/.dub/packages/dub-1.10.0/dub ]
# is non-interactive with --version=
$DUB remove dub --version=\*
if [ -d $HOME/.dub/packages/dub-1.9.0/dub ] || [ -d $HOME/.dub/packages/dub-1.10.0/dub ]; then
    die $LINENO 'Failed to non-interactively remove specified versions'
fi
