#!/usr/bin/env bash
. $(dirname "${BASH_SOURCE[0]}")/common.sh
DIR=$(dirname "${BASH_SOURCE[0]}")
packname="custom-dub-init-type-sample"

$DUB remove custom-dub-init-dubpackage --non-interactive --version=* 2>/dev/null || true
$DUB init -n $packname --format sdl -t custom-dub-init-dubpackage --skip-registry=all --registry=file://"$DIR"/issue1651-custom-dub-init-type -- --foo=bar

function cleanup {
    rm -rf $packname
}

if [ ! -e $packname/dub.sdl ]; then # it failed
    cleanup
    die $LINENO 'No dub.sdl file has been generated.'
fi

cd $packname
if ! { ${DUB} 2>&1 || true; } | grep -cF 'foo=bar'; then
	cd ..
	cleanup
	die $LINENO 'Custom init type.'
fi
cd ..
cleanup