#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd ${CURR_DIR}/1-exec-simple

# Test --colors=off disabling colors correctly
${DUB} build --colors=off --compiler=${DC} 2>&1 | { ! \grep $'^\x1b\[' -c; }

# Test --colors=automatic detecting no TTY
${DUB} build --colors=automatic --compiler=${DC} 2>&1 | { ! \grep $'^\x1b\[' -c; }

# Test no --colors= option defaulting to automatic
${DUB} build --compiler=${DC} 2>&1 | { ! \grep $'^\x1b\[' -c; }

# Test --colors=on enabling colors in any case
${DUB} build --colors=on --compiler=${DC} 2>&1 | \grep $'^\x1b\[' -c
