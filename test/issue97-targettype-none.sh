#!/usr/bin/env bash
set -e

${DUB} build --root ${CURR_DIR}/issue97-targettype-none 2>&1 || true

# make sure both sub-packages are cleaned
OUTPUT=`${DUB} clean --root ${CURR_DIR}/issue97-targettype-none 2>&1`
echo $OUTPUT | grep -c "Cleaning package at .*/issue97-targettype-none/a/" > /dev/null
echo $OUTPUT | grep -c "Cleaning package at .*/issue97-targettype-none/b/" > /dev/null
