#!/bin/bash

set -eu -o pipefail
set -x
$DUB remove --version="*" gitcompatibledubpackage || true

# check whether the interactive run mode works
echo "y" | $DUB run gitcompatibledubpackage | grep "Hello DUB"
$DUB remove gitcompatibledubpackage

! (echo "n" | $DUB run gitcompatibledubpackage | grep "Hello DUB")
! $DUB remove gitcompatibledubpackage

# check -y
$DUB run --yes gitcompatibledubpackage | grep "Hello DUB"
$DUB remove gitcompatibledubpackage

# check --yes
$DUB run -y gitcompatibledubpackage | grep "Hello DUB"
$DUB remove gitcompatibledubpackage

(! $DUB run --non-interactive gitcompatibledubpackage || true) 2>&1 | \
    grep "Failed to find.*gitcompatibledubpackage.*locally"

# check supplying versions directly
dub_log="$($DUB run gitcompatibledubpackage@1.0.3)"
echo "$dub_log" | grep "Hello DUB"
echo "$dub_log" | grep "Fetching.*1.0.3"
$DUB remove gitcompatibledubpackage

# check supplying an invalid version
(! $DUB run gitcompatibledubpackage@0.42.43 || true) 2>&1 | \
    grep 'No package gitcompatibledubpackage was found matching the dependency 0[.]42[.]43'

! $DUB remove gitcompatibledubpackage
