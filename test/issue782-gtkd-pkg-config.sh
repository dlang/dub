#!/bin/sh

if [ "${DC}" != "dmd" ]; then
	echo "Skipping issue782-dtkd-pkg-config test for ${DC}..."
else
    echo ${CURR_DIR-$(pwd)}
    # the ${CURR_DIR-$(pwd)} allows running issue782-gtkd-pkg-config.sh stand-alone from the test directory
    cd ${CURR_DIR-$(pwd)}/issue782-gtkd-pkg-config
    rm -rf fake-gtkd/.dub
    rm fake-gtkd/libfake-gtkd.so
    rm -rf main/.dub
    rm main/fake-gtkd-test
    echo ${DUB}
    cd fake-gtkd && ${DUB} build -v --compiler=${DC} || exit 1
    cd ../main

    # `run` needs to find the fake-gtkd shared library, so set LD_LIBRARY_PATH to where it is
    # pkg-config needs to find our .pc file which is in $(pwd)/../fake-gtkd/pkgconfig, so set PKG_CONFIG_PATH accordingly
    LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:$(pwd)/../fake-gtkd PKG_CONFIG_PATH=$(pwd)/../fake-gtkd/pkgconfig ${DUB} -v run --force --compiler=${DC} || exit 1
    cd ..
    rm -rf fake-gtkd/.dub
    rm fake-gtkd/libfake-gtkd.so
    rm -rf main/.dub
    rm main/fake-gtkd-test
fi
