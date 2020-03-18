#!/usr/bin/env bash
set -e

. $(dirname "${BASH_SOURCE[0]}")/common.sh

rm -rf ${CURR_DIR}/issue1504-envvar-in-path/.dub
rm -rf ${CURR_DIR}/issue1504-envvar-in-path/test
rm -rf ${CURR_DIR}/output-1504.txt


export MY_VARIABLE=teststrings 
# pragma(msg) outputs to stderr
${DUB} build --force --root ${CURR_DIR}/issue1504-envvar-in-path 2> ${CURR_DIR}/output-1504.txt

grep "env_variables_work" < ${CURR_DIR}/output-1504.txt

# Don't manage to make it work
#grep "Invalid source" < ${CURR_DIR}/output-1504.txt && true

