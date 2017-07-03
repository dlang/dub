SOURCE_FILE=$_

set -ueEo pipefail

function error {
    >&2 echo "Error: $SOURCE_FILE failed at line $1"
}
trap 'error $LINENO' ERR
