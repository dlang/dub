#!/usr/bin/env bash
set -e

OUTPUT=`${DUB} build --root ${CURR_DIR}/issue1194-warn-wrong-subconfig 2>&1 || true`

# make sure the proper errors occur in the output
echo $OUTPUT | grep -c "sub configuration directive \"bar\" -> \"baz\" references a package that is not specified as a dependency" > /dev/null
echo $OUTPUT | grep -c "sub configuration directive \"staticlib-simple\" -> \"foo\" references a configuration that does not exist" > /dev/null
! echo $OUTPUT | grep -c "sub configuration directive \"sourcelib-simple\" -> \"library\" references a package that is not specified as a dependency" > /dev/null
! echo $OUTPUT | grep -c "sub configuration directive \"sourcelib-simple\" -> \"library\" references a configuration that does not exist" > /dev/null

# make sure no bogs warnings are issued for packages with no sub configuration directives
OUTPUT=`${DUB} build --root ${CURR_DIR}/1-exec-simple 2>&1`
! echo $OUTPUT | grep -c "sub configuration directive.*references" > /dev/null
