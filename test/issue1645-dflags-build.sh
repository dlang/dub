#!/usr/bin/env bash

set -e

# If DFLAGS are not processed, dub for library would fail
DFLAGS="-w" $DUB build --root="$CURR_DIR"/1-staticLib-simple --build=plain
if DFLAGS="-asfdsf" $DUB build --root="$CURR_DIR"/1-staticLib-simple --build=plain 2>/dev/null; then
  echo "Should not accept this DFLAGS";
  false # fail
fi
$DUB build --root="$CURR_DIR"/1-staticLib-simple --build=plain --build=plain
