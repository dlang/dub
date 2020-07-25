#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

$DUB add-local "$CURR_DIR/version-spec/oldfoo"
$DUB add-local "$CURR_DIR/version-spec/newfoo"

$DUB describe foo
$DUB describe foo@1.0.0
$DUB describe foo@0.1.0

$DUB test foo
$DUB test foo@1.0.0
$DUB test foo@0.1.0

$DUB lint foo
$DUB lint foo@1.0.0
$DUB lint foo@0.1.0

$DUB generate cmake foo
$DUB generate cmake foo@1.0.0
$DUB generate cmake foo@0.1.0

$DUB build -n foo
$DUB build -n foo@1.0.0
$DUB build -n foo@0.1.0

$DUB run -n foo
$DUB run -n foo@1.0.0
$DUB run -n foo@0.1.0

$DUB remove-local "$CURR_DIR/version-spec/oldfoo"
$DUB remove-local "$CURR_DIR/version-spec/newfoo"