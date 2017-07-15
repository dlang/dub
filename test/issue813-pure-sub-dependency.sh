#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue813-pure-sub-dependency
rm -rf main/.dub
rm -rf sub/.dub
rm -rf sub/sub/.dub
rm -f main/dub.selections.json
${DUB} build --bare --compiler=${DC} main
