%{!?python_sitearch: %define python_sitearch %(%{__python} -c "from distutils.sysconfig import get_python_lib; print get_python_lib(1)")}
%{!?python_version: %define python_version %(%{__python} -c "from distutils.sysconfig import get_python_version; print get_python_version()")}

Name: dbxml
Summary: An embeddable XML database with XQuery-based access to documents
Group: System Environment/Libraries
Version: 2.3.11
Release: 1%{?dist}
License: BSD
URL: http://www.oracle.com/technology/software/products/berkeley-db/xml/index.html
# Source tarball from Oracle containing sources of db4, xercesc, xqilla
# and dbxml library itself
# Source0: http://download.oracle.com/berkeley-db/dbxml-2.3.10.tar.gz
#
# New tarball with db4, xercesc, xqilla and perl sources removed
Source0: dbxml-2.3.11-pSPS.tar.gz
Patch0: dbxml-standalone-build.patch
Patch1: dbxml-python-build.patch
Patch2: dbxml-python25-types.patch
Patch3: dbxml-os-clock.patch

BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-build

BuildRequires: automake autoconf libtool
BuildRequires: python-devel
BuildRequires: db4-devel >= 4.3.28
BuildRequires: xerces-c-devel >= 2.7.0
BuildRequires: xqilla10-devel >= 1.0.2

Requires: db4 >= 4.3.28 xerces-c >= 2.7.0 xqilla10 >= 1.0.2

%define install_prefix %{buildroot}%{_usr}
%define install_libdir %{buildroot}%{_libdir}
%define install_docdir %{buildroot}%{_defaultdocdir}

%description
Oracle Berkeley DB XML is an open source, embeddable XML database with
XQuery-based access to documents stored in containers and indexed based
on their content. Oracle Berkeley DB XML is built on top of Oracle Berkeley DB
and inherits its rich features and attributes. Like Oracle Berkeley DB, it runs
in process with the application with no need for human administration.
Oracle Berkeley DB XML adds a document parser, XML indexer and XQuery engine
on top of Oracle Berkeley DB to enable the fastest, most efficient
retrieval of data.

%package utils
Summary: Command line tools for managing Oracle DB XML database
Group: Applications/Databases
Version: %{version}
Release: %{release}
License: BSD
URL: http://www.oracle.com/technology/software/products/berkeley-db/xml/index.html
Requires: %{name} = %{version}-%{release} db4 >= 4.3.28

%description utils
Oracle Berkeley DB XML is an open source, embeddable XML database with
XQuery-based access to documents stored in containers and indexed based
on their content. Oracle Berkeley DB XML is built on top of Oracle Berkeley DB
and inherits its rich features and attributes. Like Oracle Berkeley DB, it runs
in process with the application with no need for human administration.
Oracle Berkeley DB XML adds a document parser, XML indexer and XQuery engine
on top of Oracle Berkeley DB to enable the fastest, most efficient
retrieval of data.

%package devel
Summary: Files needed to develop application using Oracle DB XML
Group: Development/Libraries
Version: %{version}
Release: %{release}
License: BSD
URL: http://www.oracle.com/technology/software/products/berkeley-db/xml/index.html
Requires: %{name} = %{version}-%{release} db4-devel >= 4.3.28

%description devel
Oracle Berkeley DB XML is an open source, embeddable XML database with
XQuery-based access to documents stored in containers and indexed based
on their content. Oracle Berkeley DB XML is built on top of Oracle Berkeley DB
and inherits its rich features and attributes. Like Oracle Berkeley DB, it runs
in process with the application with no need for human administration.
Oracle Berkeley DB XML adds a document parser, XML indexer and XQuery engine
on top of Oracle Berkeley DB to enable the fastest, most efficient
retrieval of data.

%package doc
Summary: Documentation for Oracle DB XML
Group: Development/Libraries
Version: %{version}
Release: %{release}
License: BSD
URL: http://www.oracle.com/technology/software/products/berkeley-db/xml/index.html

%description doc
Oracle Berkeley DB XML is an open source, embeddable XML database with
XQuery-based access to documents stored in containers and indexed based
on their content. Oracle Berkeley DB XML is built on top of Oracle Berkeley DB
and inherits its rich features and attributes. Like Oracle Berkeley DB, it runs
in process with the application with no need for human administration.
Oracle Berkeley DB XML adds a document parser, XML indexer and XQuery engine
on top of Oracle Berkeley DB to enable the fastest, most efficient
retrieval of data.

%package python
Summary: Python bindings for Oracle DB XML
Group: Development/Languages
Version: %{version}
Release: %{release}
License: BSD
URL: http://www.oracle.com/technology/software/products/berkeley-db/xml/index.html
Requires: %{name} = %{version}-%{release}

%description python
Oracle Berkeley DB XML is an open source, embeddable XML database with
XQuery-based access to documents stored in containers and indexed based
on their content. Oracle Berkeley DB XML is built on top of Oracle Berkeley DB
and inherits its rich features and attributes. Like Oracle Berkeley DB, it runs
in process with the application with no need for human administration.
Oracle Berkeley DB XML adds a document parser, XML indexer and XQuery engine
on top of Oracle Berkeley DB to enable the fastest, most efficient
retrieval of data.

%prep
libdb4_version() {
`ls "%{_libdir}"/libdb_cxx-?.?.so | sed 's/.*db_cxx-\(.*\).so/\1/'`
}
%setup -q -n %{name}-%{version}
%patch0
%patch1
%if "%{python_version}" > "2.4"
%patch2
%endif 
%if "libdb4_version" > "4.5"
%patch3
%endif

%build
export CPPFLAGS="-I%{_includedir}/xqilla10"
export CFLAGS="$RPM_OPT_FLAGS -fno-strict-aliasing"
export CXXFLAGS="$RPM_OPT_FLAGS -fno-strict-aliasing"

pushd src/python
sed -i "s!\"../../build_unix/.libs\"!\"../../build_unix/.libs\",\"%{_libdir}\"!" setup.py.template
sed -i "s!\"../../include\"!\"../../include\",\"%{_includedir}\"!" setup.py.template
popd
pushd dist
chmod a+x s_paths
sh s_readme
sh s_config
sh s_include
sh s_perm
sh s_python
popd
pushd build_unix
../dist/configure \
	--program-prefix= \
	--prefix=%{_prefix} \
	--exec-prefix=%{_exec_prefix} \
	--bindir=%{_bindir} \
	--sbindir=%{_sbindir} \
	--sysconfdir=%{_sysconfdir} \
	--datadir=%{_datadir} \
	--includedir=%{_includedir} \
	--libdir=%{_libdir} \
	--libexecdir=%{_libexecdir} \
	--localstatedir=%{_localstatedir} \
	--sharedstatedir=%{_sharedstatedir} \
	--mandir=%{_mandir} \
	--infodir=%{_infodir} \
	--with-berkeleydb=%{_prefix} \
	--with-xerces=%{_prefix} \
	--with-xqilla=%{_prefix} \
	--disable-java \
	--disable-tcl \
	--disable-test \
	--enable-shared \
	--disable-static
sed -i 's|^hardcode_libdir_flag_spec=.*|hardcode_libdir_flag_spec=""|g' libtool
sed -i 's|^runpath_var=LD_RUN_PATH|runpath_var=DIE_RPATH_DIE|g' libtool
make # parallel make is not supported
popd

# dbxml-python
pushd src/python
%{__python} setup.py build
popd

%install
rm -rf %{buildroot}
export CPPROG="cp -p"

# dbxml
fix_encoding() {
for file in "$@"; do
	if grep -q 'encoding="' $file; then
		enc=$(grep 'encoding="' $file | sed 's/.\+encoding="\(.\+\)"\ .\+/\1/')
		if  [ "$enc" != "UTF-8" ]; then
			iconv -f $enc -t "UTF-8" $file > tmp
			sed -i s/"$enc"/"UTF-8"/ tmp
			mv tmp $file
		fi
	fi
done
}
pushd build_unix
make install DESTDIR=%{buildroot}
mkdir -p %{install_docdir}/dbxml-%{version}
mkdir -p %{install_docdir}/dbxml-devel-%{version}
mkdir -p %{install_docdir}/dbxml-doc-%{version}
popd
cp -p LICENSE README %{install_docdir}/dbxml-%{version}/
mv %{install_prefix}/docs/* %{install_docdir}/dbxml-doc-%{version}/
rmdir %{install_prefix}/docs
mkdir -p %{install_docdir}/dbxml-devel-%{version}/examples
cp -pr examples/cxx examples/xmlData \
	%{install_docdir}/dbxml-devel-%{version}/examples
find %{install_docdir}/dbxml-devel-%{version} -name "*.cmd" -exec chmod 0644 {} ';'
find %{install_docdir}/dbxml-devel-%{version} -name "*.sh" -exec chmod 0644 {} ';'
fix_encoding `find %{install_docdir}/dbxml-doc-%{version} -name "*.html"`

# dbxml-python
pushd src/python
%{__python} setup.py install --skip-build --root %{buildroot}
mkdir -p %{install_docdir}/dbxml-python-%{version}/
cp -p README.exceptions %{install_docdir}/dbxml-python-%{version}/
popd
cp -p examples/python/examples.py %{install_docdir}/dbxml-python-%{version}/

find %{buildroot} -name "*.la" -exec rm -f {} ';'
find %{buildroot} -name "*%{name}-*.egg-info*" -exec rm -f {} ';'


%clean
rm -rf %{buildroot}

%post -p /sbin/ldconfig

%postun -p /sbin/ldconfig

%files 
%defattr(-,root,root,-)
%attr(0755,root,root) %{_libdir}/libdbxml-?.?.so
%{_defaultdocdir}/dbxml-%{version}

%files utils
%defattr(-,root,root,-)
%attr(0755,root,root) %{_bindir}/dbxml*
%attr(0755,root,root) %{_bindir}/query_runner

%files devel
%defattr(-,root,root,-)
%attr(0755,root,root) %{_libdir}/libdbxml-?.so
%attr(0755,root,root) %{_libdir}/libdbxml.so
%{_includedir}/dbxml/
%{_defaultdocdir}/dbxml-devel-%{version}

%files doc
%defattr(-,root,root,-)
%{_defaultdocdir}/dbxml-doc-%{version}

%files python
%defattr(-,root,root,-)
%{python_sitearch}/dbxml.py*
%attr(0755,root,root) %{python_sitearch}/_dbxml.so
%{_defaultdocdir}/dbxml-python-%{version}

%changelog
* Fri Sep 03 2010 Tom Throckmorton <throck@mcnc.org> - 2.3.11-1
- rebuild for 2.3.11
- remove 2.3.10 patches, as these appear either to have been incorporated
  upstream, or else they were here to mimic fixes in 2.3.11

* Thu Jan 03 2008 Milan Zazrivec <mzazrivec@redhat.com> 2.3.10-9
- Removed dbxml-perl and made it a standalone package

* Tue Dec 18 2007 Milan Zazrivec <mzazrivec@redhat.com> - 2.3.10-9
- db4, xercesc and xqilla sources removed from source tarball
- dbxml depends on xqilla10

* Sun Oct 28 2007 Milan Zazrivec <mzazrivec@redhat.com> - 2.3.10-9
- Compile against Berkeley DB 4.6
- Merged upstream patches from Oracle

* Thu Jul 19 2007 Milan Zazrivec <mzazrivec@redhat.com> - 2.3.10-5
- Initial packaging
