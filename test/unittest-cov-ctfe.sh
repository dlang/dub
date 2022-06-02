#!/usr/bin/env bash

DIR=$(dirname "${BASH_SOURCE[0]}")

. "$DIR"/common.sh

DFLAGS='-cov=100' "$DUB" test --root "$DIR"/unittest-cov-ctfe --build=unittest-cov-ctfe
