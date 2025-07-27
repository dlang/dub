#!/usr/bin/env bash

echo 'This script is deprecated. Call `dub --root run_unittest` instead'
sleep 1
exec "${DUB:-../bin/dub}" run --root=run_unittest -- -j1 "${@}"
