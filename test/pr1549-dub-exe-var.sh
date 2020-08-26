#! /usr/bin/env bash
set -e

. $(dirname "${BASH_SOURCE[0]}")/common.sh

PR1549=$CURR_DIR/pr1549-dub-exe-var

${DUB} build --root ${PR1549}
OUTPUT=$(${PR1549}/test-application)

if [[ "$OUTPUT" != "modified code" ]]; then die $LINENO "\$DUB build variable was (likely) not evaluated correctly"; fi
