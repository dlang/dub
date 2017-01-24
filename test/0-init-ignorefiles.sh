#!/bin/bash

packname="0-init-ignorefiles-pack"

function cleanup {
    rm -rf $packname
}

$DUB init -n $packname --repo=git
if [ ! -e $packname/.gitignore ]; then
	echo "No .gitignore file was generated."
    cleanup
    exit 1
fi
cleanup

$DUB init -n $packname --repo=hg
if [ ! -e $packname/.hgignore ]; then
	echo "No .hgignore file was generated."
    cleanup
    exit 1
fi

cleanup
exit 0
