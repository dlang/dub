#!/usr/bin/env bash
set -e

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cat << EOF | $DUB - || die "Did not pass minDubVersion \"1.0\""
/+ dub.sdl:
    minDubVersion "1.0"
+/
void main() {}
EOF

! cat << EOF | $DUB - || die "Did pass minDubVersion \"99.0\""
/+ dub.sdl:
    minDubVersion "99.0"
+/
void main() {}
EOF
