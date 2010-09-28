%define _unpackaged_files_terminate_build  1
%define _missing_doc_files_terminate_build 1

%define xqilla_release 2
%define xercesc_dir xerces-c-src_2_7_0

Name: xqilla10
Summary: XQilla is an XQuery and XPath 2.0 library, built on top of Xerces-C
Group: System Environment/Libraries
Version: 1.0.2
Release: %{xqilla_release}%{?dist}
License: BSD
URL: http://xqilla.sourceforge.net/HomePage
Source0: http://downloads.sourceforge.net/xqilla/XQilla-%{version}.tar.gz
Source1: http://archive.apache.org/dist/xml/xerces-c/Xerces-C_2_7_0/source/xerces-c-src_2_7_0.tar.gz
Requires: libstdc++ >= 4.1.1 xerces-c >= 2.7.0

BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-build
BuildRequires: xerces-c-devel >= 2.7.0 
BuildRequires: autoconf automake libtool

Patch0: xqilla10-xercesc-libdir.patch
Patch1:	xqilla10-10-namespace.patch

%define xercesc_build_root %{_builddir}/%{xercesc_dir}

%description
XQilla is an XQuery and XPath 2.0 implementation written in C++ and based
on Xerces-C. It implements the DOM 3 XPath API, as well as having it's own
more powerful API. It conforms to the W3C proposed recomendation of XQuery
and XPath 2.0.

%package devel
Group: Development/Libraries
Summary: XQilla is an XQuery and XPath 2.0 library, built on top of Xerces-C
Requires: %{name} = %{version}-%{release} xerces-c-devel = 2.7.0

%description devel
XQilla is an XQuery and XPath 2.0 implementation written in C++ and based
on Xerces-C. It implements the DOM 3 XPath API, as well as having it's own
more powerful API. It conforms to the W3C proposed recomendation of XQuery
and XPath 2.0.

%prep
%setup -q -b 1 -n XQilla-1.0.2
%patch0
%patch1

%build
rm -f aclocal.m4
aclocal
libtoolize --force --copy
automake --add-missing --copy --force
autoconf
%configure \
	--disable-static \
	--disable-rpath \
	--with-xerces=%{xercesc_build_root} \
	--program-suffix="10"
sed -i 's|^hardcode_libdir_flag_spec=.*|hardcode_libdir_flag_spec=""|g' libtool
sed -i 's|^runpath_var=LD_RUN_PATH|runpath_var=DIE_RPATH_DIE|g' libtool
make

%install
rm -rf %{buildroot}
export CPPROG="cp -p"
make install DESTDIR=%{buildroot}
mkdir %{buildroot}%{_includedir}/xqilla10
mv %{buildroot}%{_includedir}/xqilla %{buildroot}%{_includedir}/xqilla10
find %{buildroot} -name '*.la' -exec rm -f '{}' ';'
mkdir -p %{buildroot}%{_defaultdocdir}/%{name}-%{version}
cp -pr LICENSE* %{buildroot}%{_defaultdocdir}/%{name}-%{version}

%clean
rm -rf %{buildroot}

%post -p /sbin/ldconfig

%postun -p /sbin/ldconfig

%files
%defattr(-,root,root,-)
%{_bindir}/xqilla10
%{_libdir}/libxqilla10.so.*
%{_defaultdocdir}/%{name}-%{version}

%files devel
%defattr(-,root,root,-)
%{_libdir}/libxqilla10.so
%{_includedir}/xqilla10

%changelog
* Sun Dec 16 2007 Milan Zazrivec <mzazrivec@redhat.com> - 1.0.2-2
- xqilla102 renamed to xqilla10

* Wed Dec 12 2007 Milan Zazrivec <mzazrivec@redhat.com> - 1.0.2-2
- adopted XQilla 1.0.2 from upstream with new MAPM library license
- xqilla101 renamed to xqilla102

* Mon Nov 12 2007 Milan Zazrivec <mzazrivec@redhat.com> - 1.0.1-4
- xqilla renamed to xqilla101
- libxqilla renamed to libxqilla101
- include files moved to /usr/include/xqilla101

* Sat Nov 10 2007 Milan Zazrivec <mzazrivec@redhat.com> - 1.0.1-3
- Initial packaging
