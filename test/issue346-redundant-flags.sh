#!/usr/bin/env bash

# FIXME: generalize test so it doesn't need to be skipped
command -v arch >/dev/null \
    && [ "$(arch)" != 'x86_64' ] \
    && >&2 echo "Skipping test due to unsuitable arch." \
    && exit 0

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd ${CURR_DIR}/issue346-redundant-flags
${DUB} build --bare --force --compiler=${DC} -a x86_64 -v main 2>&1 | { ! grep -e '-m64 -m64' -c; }
