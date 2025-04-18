#!/usr/bin/env bash

DIR=$(dirname "${BASH_SOURCE[0]}")
. "$DIR"/common.sh
"$DUB" test --root "$DIR"/unittest-cov-ctfe --build=unittest-cov-ctfe
