#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh
DIR=$(dirname "${BASH_SOURCE[0]}")
packname="fetch-sub-package-dubpackage"
sub_packagename="my-sub-package"

$DUB remove $packname --non-interactive 2>/dev/null || true
$DUB fetch "$packname:$sub_packagename" --skip-registry=all --registry=file://"$DIR"/issue1567-fetch-sub-package

if ! dub remove $packname --non-interactive --version=1.0.1 2>/dev/null; then
    die 'DUB did not install package $packname:$sub_packagename.'
fi
