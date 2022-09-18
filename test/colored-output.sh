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

# Test forwarding to dmd flag -color

# Test that --color=on set dmd flag -color
${DUB} build -v --color=on --compiler=${DC} -f 2>&1 | \grep '\-color' -c

# Test that --color=off set no dmd flag
${DUB} build -v --color=off --compiler=${DC} -f 2>&1 | { ! \grep '\-color' -c; }

# Test that --color=automatic set no dmd flag
${DUB} build -v --color=automatic --compiler=${DC} -f 2>&1 | { ! \grep '\-color' -c; }
