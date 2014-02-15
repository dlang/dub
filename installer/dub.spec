# command is:
# rpmbuild -ba dub.spec --define 'gitdir /usr/src/dub' --define 'ver 0.9.21' --define 'rel rc3' --define 'commit 9d704b76112367a348446f57ef24635c9a60f4df'
# rpm file will be in ~/rpmbuild/RPMS/x86_64/dub*.rpm
# if built on a i386 platform, rpm file will be in ~/rpmbuild/RPMS/i386/dub*.rpm

Summary: D Package Manager
Name: dub
Version: %{ver}
Release: %{rel}
License: MIT
Group: Applications/Programming

#Source1: dub.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id} -u -n)
URL: http://code.dlang.org

Vendor: rejectedsoftware e.K.

BuildRequires: wget tar git

%description
Package Manager for the D Programming language

%prep
echo prep
cd %{gitdir} && git checkout ${commit}

%build
echo build
cd %{gitdir} && ./build.sh

%install
echo install
rm -fr $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT%{_bindir}/
cp %{gitdir}/bin/dub $RPM_BUILD_ROOT%{_bindir}/


#////////////////////////////////////////////////////////////////
%files
#
# list all files that need to be copied here
#

%defattr(755,root,root,-)
/usr/bin/dub


%clean
cp $RPM_BUILD_ROOT/../../RPMS/*/dub*.rpm %{gitdir}/installer
rm -fR $RPM_BUILD_ROOT/../../RPMS/*