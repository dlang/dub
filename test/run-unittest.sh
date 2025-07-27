#!/usr/bin/env bash

cd "$(dirname "${0}")"
echo "This script is deprecated. Call \`dub --root ${PWD}/run_unittest\` instead"
sleep 1
exec "${DUB:-../bin/dub}" run --root=run_unittest -- -j1 "${@}"
