#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
cd "${CURR_DIR}/issue1053-extra-files-visuald" || die "Could not cd."

"$DUB" generate visuald

if [ `grep -c -e "saturate.vert" .dub/extra_files.visualdproj` -ne 1 ]; then
	die $LINENO 'Regression of issue #1053.'
fi

if [ `grep -c -e "warp.geom" .dub/extra_files.visualdproj` -ne 1 ]; then
	die $LINENO 'Regression of issue #1053.'
fi

if [ `grep -c -e "LICENSE.txt" .dub/extra_files.visualdproj` -ne 1 ]; then
	die $LINENO 'Regression of issue #1053.'
fi

if [ `grep -c -e "README.txt" .dub/extra_files.visualdproj` -ne 1 ]; then
	die $LINENO 'Regression of issue #1053.'
fi

if [ `grep -e "README.txt" .dub/extra_files.visualdproj | grep -c -e 'copy /Y $(InputPath) $(TargetDir)'` -ne 1 ]; then
	die $LINENO 'Copying of copyFiles seems broken for visuald.'
fi

# Check that both build events contain the recipe commands in order (#426).
project=.dub/extra_files.visualdproj
pre=$(sed -n '/<preBuildCommand>/,/<\/preBuildCommand>/p' "$project")
post=$(sed -n '/<postBuildCommand>/,/<\/postBuildCommand>/p' "$project")
[[ "$pre" == *'echo extra_files ^&gt; build.txt'*'more ^&lt; build.txt ^&amp;^&amp; echo ready'* ]] ||
	die $LINENO 'Missing or out-of-order pre-build commands.'
[[ "$post" == *'echo done ^&gt;^&gt; build.txt'* ]] ||
	die $LINENO 'Missing post-build command.'
