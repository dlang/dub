# command is:
# rpmbuild -ba dub.spec --define 'ver 0.9.21' --define 'rel rc3' --define 'commit 9d704b76112367a348446f57ef24635c9a60f4df'
# rpm file will be in ~/rpmbuild/RPMS/x86_64/dub*.rpm
# if built on a i386 platform, rpm file will be in ~/rpmbuild/RPMS/i386/dub*.rpm

Summary: D Package Manager
Name: dub
Version: %{ver}
Release: %{rel}
License: MIT
Group: Applications/Programming

Source1: dub.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id} -u -n)
URL: http://code.dlang.org

Vendor: rejectedsoftware e.K.

BuildRequires: wget tar git libcurl-devel
Requires: libcurl

%description
Package Manager for the D Programming language

%prep
echo prep
cd $RPM_BUILD_DIR
rm -fr $RPM_BUILD_DIR/rejectedsoftware-dub*/
wget --no-check-certificate -O %{SOURCE1} https://github.com/rejectedsoftware/dub/tarball/%{commit}
tar -xzvf %{SOURCE1}
mv rejectedsoftware-dub*/ $RPM_BUILD_DIR/dub

%build
echo build
cd $RPM_BUILD_DIR/dub
./build.sh

%install
echo install
rm -fr $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT%{_bindir}/
cp $RPM_BUILD_DIR/dub/bin/dub $RPM_BUILD_ROOT%{_bindir}/


#////////////////////////////////////////////////////////////////
%files
#
# list all files that need to be copied here
#

%defattr(755,root,root,-)
/usr/bin/dub


%clean
rm -fr $RPM_BUILD_DIR/dub*