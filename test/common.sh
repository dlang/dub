SOURCE_FILE=$_

set -ueEo pipefail

function log() {
    echo -e "\033[0;33m[INFO] $@\033[0m"
    echo "[INFO]  $@" >> $(dirname "${BASH_SOURCE[0]}")/test.log
}

# lineno[, msg]
function die() {
    local line=$1
    local msg=${2:-command failed}
    local supplemental=${3:-}
    echo "[ERROR] $SOURCE_FILE:$1 $msg" | tee -a $(dirname "${BASH_SOURCE[0]}")/test.log | cat 1>&2
    if [ ! -z "$supplemental" ]; then
        echo "$supplemental" | >&2 sed 's|^|        |g'
    fi
    exit 1
}
trap 'die $LINENO' ERR

# Get a random port for the test to use
# This isn't foolproof but should fail less than handcrafted approaches
function getRandomPort() {
    # Get the PID of this script as a way to get a random port,
    # and make sure the value is > 1024, as ports < 1024 are priviledged
    # and require root priviledges.
    # We also need to make sure the value is not > ushort.max
    PORT=$(($$ % 65536))
    if [ $PORT -le 1024 ]; then
        PORT=$(($PORT + 1025))
    fi
    echo $PORT
}
