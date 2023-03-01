#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cd ${CURR_DIR}/1-exec-simple

# Test that --color=never disables colors correctly
printf "Expecting 0: "
${DUB} build --color=never --compiler=${DC} 2>&1 | { ! \grep $'^\x1b\[' -c; }

# Test that --color=auto detects no TTY correctly
printf "Expecting 0: "
${DUB} build --color=auto --compiler=${DC} 2>&1 | { ! \grep $'^\x1b\[' -c; }

# Test that no --color= has same behaviour as --color=auto
printf "Expecting 0: "
${DUB} build --compiler=${DC} 2>&1 | { ! \grep $'^\x1b\[' -c; }

# Test that --color=always enables colors in any case
printf "Expecting non-0: "
${DUB} build --color=always --compiler=${DC} 2>&1 | \grep $'^\x1b\[' -c

# Test forwarding to dmd flag -color

# Test that --color=always set dmd flag -color
printf "Expecting non-0: "
${DUB} build -v --color=always --compiler=${DC} -f 2>&1 | \grep '\-color' -c

# Test that --color=never set no dmd flag
printf "Expecting 0: "
${DUB} build -v --color=never --compiler=${DC} -f 2>&1 | { ! \grep '\-color' -c; }

# Test that --color=auto set no dmd flag
printf "Expecting 0: "
${DUB} build -v --color=auto --compiler=${DC} -f 2>&1 | { ! \grep '\-color' -c; }
