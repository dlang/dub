Summary: D Package Manager
Name: dub
Version: 0.9.21
Release: rc3
License: MIT
Group: Applications/Programming

Source1: dub.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id} -u -n)
URL: http://code.dlang.org

Vendor: rejectedsoftware e.K.

BuildRequires: wget tar git
Requires: libcurl libcurl-devel
ExclusiveArch: x86_64

%description
Package Manager for the D Programming language

%prep
echo prep
cd $RPM_BUILD_DIR
rm -fr $RPM_BUILD_DIR/rejectedsoftware-dub*/
wget --no-check-certificate -O %{SOURCE1} https://github.com/rejectedsoftware/dub/tarball/master
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