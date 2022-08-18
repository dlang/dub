#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd ${CURR_DIR}/1-exec-simple

# Test that --color=off disables colors correctly
${DUB} build --color=off --compiler=${DC} 2>&1 | { ! \grep $'^\x1b\[' -c; }

# Test that --color=automatic detects no TTY correctly
${DUB} build --color=automatic --compiler=${DC} 2>&1 | { ! \grep $'^\x1b\[' -c; }

# Test that no --color= has same behaviour as --color=automatic
${DUB} build --compiler=${DC} 2>&1 | { ! \grep $'^\x1b\[' -c; }

# Test that --color=on enables colors in any case
${DUB} build --color=on --compiler=${DC} 2>&1 | \grep $'^\x1b\[' -c
