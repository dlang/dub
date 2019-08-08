#!/usr/bin/env bash

cd ${CURR_DIR}/issue1070-init-mistakes-dirs-as-files

${DUB} init 2>&1 | grep -c "The target directory already contains a 'source/' directory. Aborting." > /dev/null