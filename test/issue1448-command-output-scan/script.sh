#! /usr/bin/env bash

# testing different syntaxes of the same thing

echo 'dub:json:{ "stringImportPaths": [ "'"${DUB_PACKAGE_DIR}"'/nonDefaultDir1" ] }'
echo 'dub:sdl:stringImportPaths "'"${DUB_PACKAGE_DIR}"'/nonDefaultDir2"'
echo 'dub:stringImportPaths "'"${DUB_PACKAGE_DIR}"'/nonDefaultDir3"'
echo 'dub:{ "stringImportPaths": [ "'"${DUB_PACKAGE_DIR}"'/nonDefaultDir4" ] }'
