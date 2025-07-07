#!/usr/bin/env bash
if [[ "$OSTYPE" == "darwin"* ]]; then
    . $(dirname "${BASH_SOURCE[0]}")/common.sh

    cd ${CURR_DIR}/frameworks
    rm -rf .dub
    rm -rf out/

    ${DUB} build
fi