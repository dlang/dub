#!/bin/bash

set -e -o pipefail
$DUB remove --version="*" gitcompatibledubpackage || true

echo "y" | $DUB run gitcompatibledubpackage -c exe

$DUB remove gitcompatibledubpackage
