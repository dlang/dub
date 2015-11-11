#!/bin/bash

set -e -o pipefail

(cd $CURR_DIR/ddox/default && $DUB build -b ddox)
grep -qF ddox_project $CURR_DIR/ddox/default/docs/index.html

$DUB add-local $CURR_DIR/ddox/custom-tool
(cd $CURR_DIR/ddox/custom && $DUB build -b ddox)
grep -qF custom-tool $CURR_DIR/ddox/custom/docs/custom_tool_output
diff $CURR_DIR/ddox/custom-tool/public/copied $CURR_DIR/ddox/custom/docs/copied
$DUB remove-local $CURR_DIR/ddox/custom-tool
