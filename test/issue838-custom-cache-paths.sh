#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh

CONFIG_FILE=$CURR_DIR/../etc/dub/settings.json

mkdir $CURR_DIR/../etc && mkdir $CURR_DIR/../etc/dub || true
echo "{\"customCachePaths\": [\"$CURR_DIR/issue838-custom-cache-paths/cache\"]}" > $CONFIG_FILE

trap "rm $CONFIG_FILE" EXIT

if ! { $DUB build --root "$CURR_DIR/issue838-custom-cache-paths" --skip-registry=all; }; then
	die $LINENO 'Failed to build package with custom cache path for dependencies.'
fi
