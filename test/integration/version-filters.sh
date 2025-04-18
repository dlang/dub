#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

$DUB build --root="$CURR_DIR/version-filters" --filter-versions
$DUB build --root="$CURR_DIR/version-filters-diamond" --filter-versions
$DUB build --root="$CURR_DIR/version-filters-source-dep" --filter-versions
$DUB build --root="$CURR_DIR/version-filters-none" --filter-versions
