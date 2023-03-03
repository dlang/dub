#!/usr/bin/env bash

set -u

# Output from this script is piped to a file by CI, being run from before a
# change has been made and after a change has been made. Then both outputs are
# compared using summary_comment_diff.sh

# cd to git folder, just in case this is manually run:
ROOT_DIR="$( cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd )"
cd ${ROOT_DIR}

dub --version
ldc2 --version

# fetch missing packages before timing
dub upgrade --missing-only

start=`date +%s`
dub build --build=release --force 2>&1 || echo "BUILD FAILED"
end=`date +%s`
build_time=$( echo "$end - $start" | bc -l )

strip bin/dub

echo "STAT:statistics (-before, +after)"
echo "STAT:executable size=$(wc -c bin/dub)"
echo "STAT:rough build time=${build_time}s"
