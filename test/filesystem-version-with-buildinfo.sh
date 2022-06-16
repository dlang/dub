#!/usr/bin/env bash
DIR=$(dirname "${BASH_SOURCE[0]}")

. "$DIR"/common.sh

${DUB} remove fs-json-dubpackage --non-interactive 2>/dev/null || true

echo "Trying to get fs-json-dubpackage (1.0.7)"
${DUB} fetch fs-json-dubpackage@1.0.7 --skip-registry=all --registry=file://"$DIR"/filesystem-version-with-buildinfo

if ! ${DUB} remove fs-json-dubpackage@1.0.7 2>/dev/null; then
    die $LINENO 'DUB did not install package from file system.'
fi
