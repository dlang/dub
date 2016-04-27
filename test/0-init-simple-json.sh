#!/bin/bash

packname="0-init-simple-pack"
currentYear=$(date +"%Y")

$DUB init -n $packname -f json

cat > $packname/dub2.json <<- EOL
{
	"name": "$packname",
	"authors": [
		"$USER"
	],
	"dependencies": {},
	"description": "A minimal D application.",
	"copyright": "Copyright © $currentYear, $USER",
	"license": "proprietary"
}
EOL

function cleanup {
    rm -rf $packname
}

diff -w $packname/dub.json $packname/dub2.json

if [ ! -e $packname/dub.json ]; then # it failed
	cleanup
	exit 1
fi
cleanup
exit 0
