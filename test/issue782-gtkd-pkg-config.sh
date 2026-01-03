#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

if [ $(uname) != "Linux" ]; then
    echo "Skipping issue782-dtkd-pkg-config test on non-Linux platform..."
elif [ "${DC}" != "dmd" ]; then
	echo "Skipping issue782-dtkd-pkg-config test for ${DC}..."
else
    echo ${CURR_DIR-$(pwd)}
    # the ${CURR_DIR-$(pwd)} allows running issue782-gtkd-pkg-config.sh stand-alone from the test directory
    cd ${CURR_DIR-$(pwd)}/issue782-gtkd-pkg-config
    rm -rf fake-gtkd/.dub
    rm -f fake-gtkd/libfake-gtkd.so
    rm -rf main/.dub
    rm -f main/fake-gtkd-test
    echo ${DUB}
    cd fake-gtkd && ${DUB} build --compiler=${DC}
    cd ../main

    # `run` needs to find the fake-gtkd shared library, so set LD_LIBRARY_PATH to where it is
    export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-}${LD_LIBRARY_PATH:+:}$PWD/../fake-gtkd
    # pkg-config needs to find our .pc file which is in $PWD/../fake-gtkd/pkgconfig, so set PKG_CONFIG_PATH accordingly
    export PKG_CONFIG_PATH=$PWD/../fake-gtkd/pkgconfig

    # Verify that pkg-config --cflags is being extracted properly
    # The .pc file includes -DFAKE_GTKD_VERSION=100 which should appear as -P-DFAKE_GTKD_VERSION=100
    VERBOSE_OUTPUT=$(${DUB} build --force --compiler=${DC} -v 2>&1)
    if ! echo "$VERBOSE_OUTPUT" | grep -q "\-P-DFAKE_GTKD_VERSION=100"; then
        echo "FAIL: pkg-config --cflags extraction not working: -P-DFAKE_GTKD_VERSION=100 not found in compiler flags"
        echo "Verbose output:"
        echo "$VERBOSE_OUTPUT"
        exit 1
    fi
    echo "PASS: pkg-config --cflags extraction working (-P-DFAKE_GTKD_VERSION=100 found)"

    # Also verify -P-I flag for cImportPaths is present
    if ! echo "$VERBOSE_OUTPUT" | grep -q "\-P-I.*fake-gtkd"; then
        echo "FAIL: pkg-config --cflags extraction not working: -P-I path not found in compiler flags"
        exit 1
    fi
    echo "PASS: pkg-config --cflags include path extraction working"

    ${DUB} run --force --compiler=${DC}
    cd ..
    rm -rf fake-gtkd/.dub
    rm fake-gtkd/libfake-gtkd.so
    rm -rf main/.dub
    rm main/fake-gtkd-test
fi
