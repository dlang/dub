SOURCE_FILE=$_

set -ueEo pipefail

# lineno[, msg]
function die() {
    local line=$1
    local msg=${2:-command failed}
    local supplemental=${3:-}
    >&2 echo "$SOURCE_FILE:$1 Error: $msg"
    if [ ! -z "$supplemental" ]; then
        echo "$supplemental" | >&2 sed 's|^|        |g'
    fi
    exit 1
}
trap 'die $LINENO' ERR
