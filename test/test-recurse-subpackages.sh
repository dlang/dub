#!/usr/bin/env bash

. $(dirname "${BASH_SOURCE[0]}")/common.sh
packname="test-recurse-subpackages"

cd $(dirname "${BASH_SOURCE[0]}")/$packname

testresultN=$($DUB test -q 2>&1)
testresultR=$($DUB test -q --recurse-subpackages 2>&1)

function check_contains() {
	if ! { echo "${1}"; } | grep -cF "${2}" > /dev/null; then
		die "${BASH_LINENO[0]}" "${3}"
	fi
}
function check_not_contains() {
	if { echo "${1}"; } | grep -cF "${2}" > /dev/null; then
		die "${BASH_LINENO[0]}" "${3}"
	fi
}


check_contains      "$testresultN" 'Root package tested.'          'Normal test was failed. Root package was not tested.'
check_contains      "$testresultR" 'Root package tested.'          'Subpackages recursive test was failed. Root package was not tested.'
check_not_contains  "$testresultN" 'Root package main is running.' 'Normal test was failed. Root package was not tested.'
check_not_contains  "$testresultR" 'Root package main is running.' 'Root package main function was called illegally.'

check_not_contains  "$testresultN" 'subpackage1 tested.'           'Normal test contains a result of subpackage illegally. Subpackage "subpkg1" was tested.'
check_contains      "$testresultR" 'subpackage1 tested.'           'Subpackages recursive test was failed. Subpackage "subpkg1" was not tested.'
check_not_contains  "$testresultN" 'subpackage1 main is running.'  'subpackage1 main function was called illegally.'
check_not_contains  "$testresultR" 'subpackage1 main is running.'  'subpackage1 main function was called illegally.'

check_not_contains  "$testresultN" 'subpackage2 tested.'           'Normal test contains a result of subpackage illegally. Subpackage "subpkg2" was tested.'
check_contains      "$testresultR" 'subpackage2 tested.'           'Subpackages recursive test was failed. Subpackage "subpkg2" was not tested.'
# subpkg2 is library, main source file is not exist.
#check_not_contains  "$testresultN" 'subpackage2 main is running.'  'subpackage2 main function was called illegally.'
#check_not_contains  "$testresultR" 'subpackage2 main is running.'  'subpackage2 main function was called illegally.'

check_not_contains  "$testresultN" 'subpackage3 tested.'           'Normal test contains a result of subpackage illegally. Subpackage "subpkg3" was tested.'
check_contains      "$testresultR" 'subpackage3 tested.'           'Subpackages recursive test was failed. Subpackage "subpkg3" was not tested.'
check_not_contains  "$testresultN" 'subpackage3 main is running.'  'subpackage3 main function was called illegally.'
check_not_contains  "$testresultR" 'subpackage3 main is running.'  'subpackage3 main function was called illegally.'
