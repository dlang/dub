#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
if [ "${DC}" != "dmd" ]; then
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
    cd fake-gtkd && ${DUB} build --compiler=${DC} || exit 1
    cd ../main

    # `run` needs to find the fake-gtkd shared library, so set LD_LIBRARY_PATH to where it is
    export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-}${LD_LIBRARY_PATH:+:}$PWD/../fake-gtkd
    # pkg-config needs to find our .pc file which is in $PWD/../fake-gtkd/pkgconfig, so set PKG_CONFIG_PATH accordingly
    export PKG_CONFIG_PATH=$PWD/../fake-gtkd/pkgconfig
    ${DUB} run --force --compiler=${DC} || exit 1
    cd ..
    rm -rf fake-gtkd/.dub
    rm fake-gtkd/libfake-gtkd.so
    rm -rf main/.dub
    rm main/fake-gtkd-test
fi
