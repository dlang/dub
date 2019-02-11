#!/usr/bin/env bash

# If DFLAGS are not processed, dub for library would fail
DFLAGS="-w" $DUB --root="$CURR_DIR"/1-staticLib-simple --build=plain
if DFLAGS="-asfdsf" $DUB --root="$CURR_DIR"/1-staticLib-simple --build=plain 2>/dev/null; then
  echo "Should not accept this DFLAGS"
fi
$DUB --root="$CURR_DIR"/1-staticLib-simple --build=plain --build=plain
