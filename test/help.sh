#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

DUB=dub

### It shows the general help message
if ! { ${DUB} help | grep "Manages the DUB project in the current directory."; } then
    die 'DUB did not print the default help message, with the `help` command.'
fi

if ! { ${DUB} -h | grep "Manages the DUB project in the current directory."; } then
    die 'DUB did not print the default help message, with the `-h` argument.'
fi

if ! { ${DUB} --help | grep "Manages the DUB project in the current directory."; } then
    die 'DUB did not print the default help message, with the `--help` argument.'
fi

### It shows the build command help
if ! { ${DUB} build -h | grep "Builds a package"; } then
    die 'DUB did not print the build help message, with the `-h` argument.'
fi

if ! { ${DUB} build --help | grep "Builds a package"; } then
    die 'DUB did not print the build help message, with the `--help` argument.'
fi
