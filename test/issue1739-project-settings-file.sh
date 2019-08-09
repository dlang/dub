#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd ${CURR_DIR}
echo "{\"defaultArchitecture\": \"foo\"}" > "dub.settings.json"

function cleanup {
    rm "dub.settings.json"
}

trap cleanup EXIT

if ! { ${DUB} describe --single issue103-single-file-package.d 2>&1 || true; } | grep -cF "Unsupported architecture: foo"; then
    die $LINENO 'DUB did not find the project configuration with an adjacent architecture.'
fi

