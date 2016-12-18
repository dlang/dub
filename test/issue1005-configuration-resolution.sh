#!/bin/sh

cd ${CURR_DIR}/issue1005-configuration-resolution
${DUB} build --bare main || exit 1
