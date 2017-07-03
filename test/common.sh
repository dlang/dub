SOURCE_FILE=$_

set -ueEo pipefail

# lineno[, msg]
function die() {
    local line=$1
    local msg=${2:-command failed}
    local rc=${3:-1}
    >&2 echo "$SOURCE_FILE:$1 Error: $msg"
    exit $rc
}
trap 'die $LINENO' ERR
