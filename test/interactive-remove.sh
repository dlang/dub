#!/bin/bash

set -euo pipefail

$DUB fetch dub --version=0.9.20 && [ -d $HOME/.dub/packages/dub-0.9.20/dub ]
$DUB fetch dub --version=0.9.21 && [ -d $HOME/.dub/packages/dub-0.9.21/dub ]
if $DUB remove dub --non-interactive; then
    echo "Non-interactive remove should fail" 1>&2
    exit 1
fi
echo 1 | $DUB remove dub | tr -d '\n' | grep --ignore-case 'select.*0\.9\.20.*0\.9\.21.*'
if [ -d $HOME/.dub/packages/dub-0.9.20/dub ]; then
    echo "Failed to remove dub-0.9.20" 1>&2
    exit 1
fi
$DUB fetch dub --version=0.9.20 && [ -d $HOME/.dub/packages/dub-0.9.20/dub ]
# EOF aborts remove
echo -xn '' | $DUB remove dub
if [ ! -d $HOME/.dub/packages/dub-0.9.20/dub ] || [ ! -d $HOME/.dub/packages/dub-0.9.21/dub ]; then
    echo "Aborted dub still removed a package" 1>&2
    exit 1
fi
# validates input
echo -e 'abc\n4\n-1\n3' | $DUB remove dub
if [ -d $HOME/.dub/packages/dub-0.9.20/dub ] || [ -d $HOME/.dub/packages/dub-0.9.21/dub ]; then
    echo "Failed to remove all version of dub" 1>&2
    exit 1
fi
$DUB fetch dub --version=0.9.20 && [ -d $HOME/.dub/packages/dub-0.9.20/dub ]
$DUB fetch dub --version=0.9.21 && [ -d $HOME/.dub/packages/dub-0.9.21/dub ]
# is non-interactive with --version=
$DUB remove dub --version=\*
if [ -d $HOME/.dub/packages/dub-0.9.20/dub ] || [ -d $HOME/.dub/packages/dub-0.9.21/dub ]; then
    echo 'Failed to non-interactively remove specified versions' 1>&2
    exit 1
fi
