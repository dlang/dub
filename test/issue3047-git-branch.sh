#!/usr/bin/env bash

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$work_dir/repository/source" "$work_dir/project/source"
git init -q "$work_dir/repository"
git -C "$work_dir/repository" checkout -qb main
git -C "$work_dir/repository" config user.name 'DUB Test'
git -C "$work_dir/repository" config user.email 'dub-test@example.invalid'
echo '{"name":"branch-dependency","targetType":"library"}' > "$work_dir/repository/dub.json"
echo 'module dependency; enum answer = 1;' > "$work_dir/repository/source/dependency.d"
git -C "$work_dir/repository" add .
git -C "$work_dir/repository" commit -qm initial
initial_commit=$(git -C "$work_dir/repository" rev-parse HEAD)
git -C "$work_dir/repository" tag release
git -C "$work_dir/repository" checkout -qb feature
echo 'module dependency; enum answer = 2;' > "$work_dir/repository/source/dependency.d"
git -C "$work_dir/repository" commit -qam feature
git -C "$work_dir/repository" branch release
git -C "$work_dir/repository" checkout -q main

check_reference() {
    local reference=$1 expected=$2
    export DUB_HOME="$work_dir/cache-$expected-$reference"
    mkdir -p "$DUB_HOME"
    rm -f "$work_dir/project/dub.selections.json"
    cat > "$work_dir/project/dub.json" <<EOF
{"name":"branch-consumer","dependencies":{"branch-dependency":{
    "repository":"git+$work_dir/repository","version":"$reference"}}}
EOF
    echo "import dependency; void main() { assert(answer == $expected); }" > "$work_dir/project/source/app.d"
    "$DUB" run --root="$work_dir/project" --compiler="${DC:-dmd}" --skip-registry=all --force
}

# The remote branch is not the clone's default branch.
check_reference '~feature' 2
check_reference '~main' 1
check_reference "$initial_commit" 1
# An existing tag must retain precedence over a remote branch of the same name.
check_reference '~release' 1
