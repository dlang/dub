#!/bin/bash

set -e -o pipefail

(cd default && $DUB build -b ddox)
grep -qF ddox_project default/docs/index.html

$DUB add-local custom-tool
(cd custom && $DUB build -b ddox)
grep -qF custom-tool custom/docs/custom_tool_output
diff custom-tool/public/copied custom/docs/copied
$DUB remove-local custom-tool
