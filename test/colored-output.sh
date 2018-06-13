#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd ${CURR_DIR}/1-exec-simple

# Test --colors=off disabling colors correctly
${DUB} build --colors=off --compiler=${DC} 2>&1 | { ! grep -P '\e\[' -c; }

# Test --colors=auto detecting no TTY
${DUB} build --colors=auto --compiler=${DC} 2>&1 | { ! grep -P '\e\[' -c; }

# Test no --colors= option defaulting to auto
${DUB} build --compiler=${DC} 2>&1 | { ! grep -P '\e\[' -c; }

# Test --colors=on enabling colors in any case
${DUB} build --colors=on --compiler=${DC} 2>&1 | grep -P '\e\[' -c
