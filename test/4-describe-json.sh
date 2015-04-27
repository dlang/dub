#!/bin/bash

set -e -o pipefail

cd "$CURR_DIR"/describe-project

temp_file=`mktemp`

function cleanup {
    rm $temp_file
}

trap cleanup EXIT

if ! $DUB describe --compiler=$COMPILER > "$temp_file"; then
    die 'Printing describe JSON failed!'
fi

declare -A expr_map

expr_map[description]='A test describe project'
expr_map[name]='describe-project'
expr_map[targetType]='sourceLibrary'
expr_map['authors[0]']='nobody'

for expression in "${!expr_map[@]}"; do
    expected="${expr_map[$expression]}"

    actual=`jq --raw-output '.packages[0].'"$expression" "$temp_file"`

    if [[ "$actual" != "$expected" ]]; then
        die "The value for $expression was wrong in the describe output!"
    fi
done
