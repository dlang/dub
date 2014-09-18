#!/bin/sh
set -e
cd ../../
DUB_PATH=`pwd`
#rm -f ~/rpmbuild/SOURCES/dub.tar.gz
#tar -pczf ~/rpmbuild/SOURCES/dub.tar.gz source build-files.txt build.sh LICENSE*
cd installer/rpm/
for i in $(git describe | tr "-" "\n"); do
	if [ "$VER" == "" ]; then
		VER=${i:1}
	elif [ "$REL" == "" ]; then
		REL=0.$i
	else
		REL=$REL.$i
	fi
done
if [ "$REL" == "" ]; then
	REL=1
fi
ARCH=$(uname -i)
echo Building RPM FOR $VER-$REL-$ARCH
rpmbuild -ba dub.spec --define "ver $VER" --define "rel $REL" --define="srcpath $DUB_PATH"
cp ~/rpmbuild/BUILD/dub-$VER-$REL.$ARCH.rpm .
