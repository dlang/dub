#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
# Check project files generated from project "root"
cd ${CURR_DIR}/issue1477-subpackage-visuald-paths
rm -rf .dub
${DUB} generate visuald :subpackage_a
if ! grep  "<File path=\"../source/library.d\"" .dub/library.visualdproj; then
	die $LINENO 'VisualD path not correct'
fi
if ! grep  "<File path=\"../sub/subpackage_a/source/subpackage_a.d\"" .dub/library_subpackage_a.visualdproj; then
	die $LINENO 'VisualD path not correct'
fi

# Check project files generated from sub package level
cd sub/subpackage_a
rm -rf .dub
${DUB} generate visuald
if ! grep  "<File path=\"../../../source/library.d\"" .dub/library.visualdproj; then
	die $LINENO 'VisualD path not correct'
fi
if ! grep  "<File path=\"../source/subpackage_a.d\"" .dub/subpackage_a.visualdproj; then
	die $LINENO 'VisualD path not correct'
fi


