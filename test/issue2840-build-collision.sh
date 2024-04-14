#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

pushd $(dirname "${BASH_SOURCE[0]}")/issue2840-build-collision
# Copy before building, as dub uses timestamp to check for rebuild
rm -rf nested/ && mkdir -p nested/ && cp -v build.d nested/

$DUB ./build.d $(pwd)/build.d
pushd nested
$DUB ./build.d $(pwd)/build.d
popd

popd
