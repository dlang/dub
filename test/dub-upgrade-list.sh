#!/usr/bin/env bash
set -e

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd "$CURR_DIR/dub-upgrade-list"

$DUB fetch gitcompatibledubpackage@1.0.1
$DUB fetch gitcompatibledubpackage@1.0.2
$DUB fetch gitcompatibledubpackage@1.0.4

rm -f dub.selections.json

$DUB upgrade -l | grep -F 'gitcompatibledubpackage  1.0.4  *NEW*'
$DUB upgrade -l -m | grep -F 'gitcompatibledubpackage  1.0.4  *NEW*'

if [ -f "dub.selections.json" ]; then die $LINENO 'dub upgrade --list should not emit any dub.selections.json.'; fi

$DUB select gitcompatibledubpackage 1.0.1

$DUB upgrade -l -m | grep -F 'gitcompatibledubpackage  1.0.1  (outdated)'
$DUB upgrade -l | grep -F 'gitcompatibledubpackage  1.0.1 -> 1.0.4'

$DUB upgrade -l --dry-run=false | grep -F 'gitcompatibledubpackage  1.0.1 -> 1.0.4'

if [ ! -f "dub.selections.json" ]; then die $LINENO 'dub upgrade --list --dry-run=false should emit a dub.selections.json.'; fi

$DUB upgrade -l -m | grep -F 'gitcompatibledubpackage  1.0.4'

$DUB deselect gitcompatibledubpackage

$DUB upgrade -l | grep -F 'gitcompatibledubpackage  1.0.4  *NEW*'
$DUB upgrade -l -m | grep -F 'gitcompatibledubpackage  1.0.4  *NEW*'
