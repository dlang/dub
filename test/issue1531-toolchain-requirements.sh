#!/usr/bin/env bash
set -e

. $(dirname "${BASH_SOURCE[0]}")/common.sh

cat << EOF | $DUB - || die "Did not pass without toolchainRequirements"
/+ dub.sdl:
+/
void main() {}
EOF

# pass test dub requirement given as $1
function test_dub_req_pass {
    cat << EOF | $DUB - || die "Did not pass requirement dub=\"$1\""
/+ dub.sdl:
    toolchainRequirements dub="$1"
+/
void main() {}
EOF
}

# fail test dub requirement given as $1
function test_dub_req_fail {
    ! cat << EOF | $DUB - || die "Did not pass requirement dub=\"$1\""
/+ dub.sdl:
    toolchainRequirements dub="$1"
+/
void main() {}
EOF
}

test_dub_req_pass ">=1.7.0"
test_dub_req_fail "~>0.9"
test_dub_req_fail "~>999.0"

# extract compiler version
if [[ $DC == *ldc* ]] || [[ $DC == *ldmd* ]]; then
    VER_REG='\((([[:digit:]]+)(\.[[:digit:]]+\.[[:digit:]]+[A-Za-z0-9.+-]*))\)'
    DC_NAME=ldc
elif [[ $DC == *dmd* ]]; then
    VER_REG='v(([[:digit:]]+)(\.[[:digit:]]+\.[[:digit:]]+[A-Za-z0-9.+-]*))'
    DC_NAME=dmd
elif [[ $DC == *gdc* ]]; then
    VER_REG='\) (([[:digit:]]+)(\.[[:digit:]]+\.[[:digit:]]+[A-Za-z0-9.+-]*))'
    DC_NAME=gdc
else
    die "Did not recognize compiler"
fi
if [[ $($DC --version) =~ $VER_REG ]]; then
    DC_VER=${BASH_REMATCH[1]}
    DC_VER_MAJ=${BASH_REMATCH[2]}
    DC_VER_REM=${BASH_REMATCH[3]}
    $DC --version
    echo $DC version is $DC_VER
else
    $DC --version
    die "Could not extract compiler version"
fi

# create test app directory
TMPDIR=$(mktemp -d /tmp/dubtest1531_XXXXXX)
mkdir -p $TMPDIR/source
cat << EOF > $TMPDIR/source/app.d
module dubtest1531;
void main() {}
EOF

# write dub.sdl with compiler requirement given as $1
function write_cl_req {
    cat << EOF > $TMPDIR/dub.sdl
name "dubtest1531"
toolchainRequirements ${DC_NAME}="$1"
EOF
}

# pass test compiler requirement given as $1
function test_cl_req_pass {
    write_cl_req $1
    $DUB --compiler=$DC --root=$TMPDIR || die "Did not pass with $DC_NAME=\"$1\""
}

# fail test compiler requirement given as $1
function test_cl_req_fail {
    write_cl_req $1
    ! $DUB --compiler=$DC --root=$TMPDIR || die "Did not fail with $DC_NAME=\"$1\""
}


test_cl_req_pass "==$DC_VER"
test_cl_req_pass ">=$DC_VER"
test_cl_req_fail ">$DC_VER"
test_cl_req_pass "<=$DC_VER"
test_cl_req_fail "<$DC_VER"
test_cl_req_pass ">=$DC_VER <$(($DC_VER_MAJ + 1))$DC_VER_REM"
test_cl_req_pass "~>$DC_VER"
test_cl_req_fail "~>$(($DC_VER_MAJ + 1))$DC_VER_REM"
test_cl_req_fail no

rm -rf $TMPDIR
