#!/usr/bin/env bash

DIR=$(dirname "${BASH_SOURCE[0]}")
. "$DIR"/common.sh
"$DUB" run --root "$DIR"/cov-ctfe --build=cov-ctfe
