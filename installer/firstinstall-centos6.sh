yum -y install rpm-build git binutils libstdc++-devel wget gcc gcc-c++ make openssl libcurl-devel tar kernel-devel
cd /usr/src
git clone https://github.com/etcimon/dub
cd dub/installer
rpmbuild -ba dmd.spec
cp ~/rpmbuild/RPMS/x86_64/dmd*.rpm ./
rpm -ivh dmd*.rpm
rpmbuild -ba dub.spec --define 'gitdir /usr/src/dub' --define 'ver 0.9.21' --define 'rel rc4' --define 'commit master'
rpm -ivh dub*.rpm
ls -l
echo "Dub and dmd are in /usr/src/dub/installer"
echo "see dub.spec for the usual rpmbuild command to rebuild dub with a different commit/version/release"
