## command is:
# rpmbuild -ba dub.spec --define 'ver 0.9.21' --define 'rel 0.rc.3'
# rpm file will be in ./dub*.rpm
# if built on a i386 platform, rpm file will be in ~/rpmbuild/RPMS/i386/dub*.rpm

Name: dub
Summary: Package manager and meta build tool for the D programming language
Vendor: rejectedsoftware e.K.
Version: %{ver}
Release: %{rel}
License: MIT
Group: Applications/Programming

#Source: dub.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id} -u -n)
URL: http://code.dlang.org

BuildRequires: tar

%description
Package Manager for the D Programming language

%prep
#echo prep
#tar -xf %{_sourcedir}/dub.tar.gz

%build
echo build
cd %{srcpath} && ./build.sh

%install
echo install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT%{_bindir}/
cp %{srcpath}/bin/dub $RPM_BUILD_ROOT%{_bindir}/

%files
#
# list all files that need to be copied here
#

%defattr(755,root,root,-)
/usr/bin/dub

%clean
cp $RPM_BUILD_ROOT/../../RPMS/*/dub*.rpm .
rm -rf $RPM_BUILD_ROOT/../../RPMS/*
