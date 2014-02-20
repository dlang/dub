Summary: Digital Mars D Compiler
Name: dmd
Version: 2.065
Release: beta3
License: Proprietary
Group: Applications/Programming

Source0: D-Programming-Language-dmd-dmd.tar.gz
Source1: D-Programming-Language-phobos-phobos.tar.gz
Source2: D-Programming-Language-druntime-druntime.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id} -u -n)
URL: http://www.digitalmars.com/

Vendor: DigitalMars
Packager: <kai@gnukai.com>

BuildRequires: binutils libstdc++-devel wget gcc gcc-c++ make openssl libcurl-devel tar kernel-devel
ExclusiveArch: x86_64

%define _archmodel 64
%define _buildcores 5

%description
Compiler for the D Programming language

%prep
rm -fr D-Programming-Language-dmd-*/
rm -fr phobos/
rm -fr druntime/
wget --no-check-certificate -O %{SOURCE0} https://github.com/D-Programming-Language/dmd/tarball/master
wget --no-check-certificate -O %{SOURCE1} https://github.com/D-Programming-Language/phobos/tarball/master
wget --no-check-certificate -O %{SOURCE2} https://github.com/D-Programming-Language/druntime/tarball/master
tar -xzvf %{SOURCE0}
tar -xzvf %{SOURCE1}
tar -xzvf %{SOURCE2}
mv $RPM_BUILD_DIR/D-Programming-Language-dmd-*/ $RPM_BUILD_DIR/dmd
mv $RPM_BUILD_DIR/D-Programming-Language-phobos-*/ $RPM_BUILD_DIR/phobos
mv $RPM_BUILD_DIR/D-Programming-Language-druntime-*/ $RPM_BUILD_DIR/druntime


%build
cd $RPM_BUILD_DIR/dmd/src/
make -f posix.mak MODEL=%{_archmodel} -j%{_buildcores}
cd $RPM_BUILD_DIR/phobos/
make -f posix.mak MODEL=%{_archmodel} -j%{_buildcores}
## Phobos will build druntime
cd $RPM_BUILD_DIR/druntime/
make -f posix.mak MODEL=%{_archmodel} -j%{_buildcores}

%install
echo install
rm -fr $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT%{_bindir} \
         $RPM_BUILD_ROOT%{_libdir} \
         $RPM_BUILD_ROOT%{_docdir}/dmd \
         $RPM_BUILD_ROOT/usr/share/dmd \
         $RPM_BUILD_ROOT/usr/include/d/dmd/druntime/ \
         $RPM_BUILD_ROOT/usr/include/d/dmd/phobos/ \
         $RPM_BUILD_ROOT/etc/
		 
		 
cp -r $RPM_BUILD_DIR/druntime/import $RPM_BUILD_ROOT/usr/include/d/dmd/druntime/
cp -r $RPM_BUILD_DIR/dmd/docs/man/man1 $RPM_BUILD_ROOT%{_mandir}
cp -r $RPM_BUILD_DIR/druntime/doc $RPM_BUILD_ROOT%{_docdir}/dmd
cp -r $RPM_BUILD_DIR/phobos/{etc,std,*.d} $RPM_BUILD_ROOT/usr/include/d/dmd/phobos/
cp $RPM_BUILD_DIR/dmd/src/dmd $RPM_BUILD_ROOT%{_bindir}/dmd
cp $RPM_BUILD_DIR/phobos/generated/linux/release/64/libphobos2.a $RPM_BUILD_ROOT%{_libdir}
cp $RPM_BUILD_DIR/phobos/generated/linux/release/64/libphobos2.so.0.65.0 $RPM_BUILD_ROOT%{_libdir}
touch $RPM_BUILD_ROOT/etc/dmd.conf
echo "[Environment]
DFLAGS=-I/usr/include/d/dmd/phobos -I/usr/include/d/dmd/druntime/import" > $RPM_BUILD_ROOT/etc/dmd.conf

#////////////////////////////////////////////////////////////////
%files
#
# list all files that need to be copied here
#

%defattr(755,root,root,-)
/usr/bin/dmd
#/usr/bin/dumpobj
#/usr/bin/obj2asm
#/usr/bin/rdmd
%defattr(-,root,root,-)
/usr/include/d/dmd
/usr/lib64/libphobos2.a
/usr/lib64/libphobos2.so.0.65.0
%doc /usr/share/man
%doc /usr/share/doc/dmd
%doc /usr/share/dmd
%config /etc/dmd.conf

%post
ln -s /usr/lib64/libphobos2.so.0.65.0 /usr/lib64/libphobos2.so.0.65
ln -s /usr/lib64/libphobos2.so.0.65.0 /usr/lib64/libphobos2.so

%preun
rm -fr /usr/lib64/libphobos2.so.0.65
rm -fr /usr/lib64/libphobos2.so

%clean
rm -fR $RPM_BUILD_DIR/dmd
rm -fR $RPM_BUILD_DIR/druntime
rm -fR $RPM_BUILD_DIR/phobos