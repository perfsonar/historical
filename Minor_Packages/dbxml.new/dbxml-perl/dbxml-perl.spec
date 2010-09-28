Name: dbxml-perl
Version: 2.003
Release: 3%{?dist}
Summary: Perl bindings for Oracle DB XML
Group: Development/Languages
License: GPL+ or Artistic 2.0
URL: http://www.oracle.com/technology/software/products/berkeley-db/xml/index.html
# Source tarball from Oracle containing sources of db4, xercesc, xqilla
# and dbxml library itself (including bindings)
# Source0: http://download.oracle.com/berkeley-db/dbxml-2.3.10.tar.gz
#
# New tarball with perl bindings only
Source0: dbxml-perl-%{version}.tar.gz
Patch0: dbxml-perl-db46-build.patch
BuildRequires: db4-devel >= 4.3.28
BuildRequires: dbxml-devel = 2.3.10
BuildRequires: xqilla10-devel >= 1.0.2
BuildRequires: perl(ExtUtils::MakeMaker)
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-build

%define install_prefix %{buildroot}%{_usr}
%define install_docdir %{buildroot}%{_defaultdocdir}
%define db4_version %(ls %{_libdir}/libdb_cxx-?.?.so | sed 's!.*db_cxx-!!' | sed 's!.so!!')

%description
Oracle Berkeley DB XML is an open source, embeddable XML database with
XQuery-based access to documents stored in containers and indexed based
on their content. Oracle Berkeley DB XML is built on top of Oracle Berkeley DB
and inherits its rich features and attributes. Like Oracle Berkeley DB, it runs
in process with the application with no need for human administration.
Oracle Berkeley DB XML adds a document parser, XML indexer and XQuery engine
on top of Oracle Berkeley DB to enable the fastest, most efficient
retrieval of data.

%prep
%setup -q -n dbxml-perl-%{version}
%if "%{db4_version}" > "4.5"
%patch0
%endif

%build
sed -i 's!CC = @CXX@!CC = g++!' "config.in"
sed -i 's!DBXML_LIB_NAME = dbxml-@DBXML_VERSION_MAJOR@.@DBXML_VERSION_MINOR@!DBXML_LIB_NAME = dbxml-2.3!' "config.in"
sed -i 's!DBXML_LIB_PATH = ../../build_unix/.libs!DBXML_LIB_PATH = %{_libdir}!' "config.in"
sed -i 's!DBXML_INC_PATH = ../../include!DBXML_INC_PATH = %{_includedir}!' "config.in"
sed -i 's!BDB_LIB_NAME = db_cxx-4!BDB_LIB_NAME = db_cxx!' "config.in"
sed -i 's!BDB_LIB_PATH = @DB_DIR@/lib!BDB_LIB_PATH = %{_libdir}!' "config.in"
sed -i 's!BDB_INC_PATH = @DB_DIR@/include!BDB_INC_PATH = %{_includedir}!' "config.in"
sed -i 's!XERCES_LIB_PATH = @XERCES_DIR@/lib!XERCES_LIB_PATH = %{_libdir}!' "config.in"
sed -i 's!XQILLA_LIB_NAME = xqilla!XQILLA_LIB_NAME = xqilla10!' "config.in"
sed -i 's!XQILLA_LIB_PATH = @XQILLA_DIR@/lib!XQILLA_LIB_PATH = %{_libdir}!' "config.in"
cp "config.in" "config"
%{__perl} Makefile.PL PREFIX=%{install_prefix} INSTALLDIRS=vendor
make OPTIMIZE="${RPM_OPT_FLAGS}"

%install
rm -rf %{buildroot}
make install
mkdir -p %{install_docdir}/dbxml-perl-%{version}/examples
cp -pr examples/gettingStarted/* \
	%{install_docdir}/dbxml-perl-%{version}/examples/
cp -p Changes README %{install_docdir}/dbxml-perl-%{version}

find %{buildroot} -name "perllocal.pod" -exec rm -f {} ';'
find %{buildroot}%{perl_vendorarch} -name "*.bs" -a -size 0 -exec rm -f {} ';'
find %{buildroot}%{perl_vendorarch} -name ".packlist" -exec rm -f {} ';'
find %{buildroot}%{perl_vendorarch} -name "*.so" -exec chmod 0755 {} ';'

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root)
%{perl_vendorarch}/auto/
%{perl_vendorarch}/Sleepycat/
%{_mandir}/man3/Sleepycat*
%{_defaultdocdir}/dbxml-perl-%{version}

%changelog
* Fri Jan 18 2008 Milan Zazrivec <mzazrivec@redhat.com> 2.003-3
- Fix db4 version check

* Mon Jan 14 2008 Milan Zazrivec <mzazrivec@redhat.com> 2.003-2
- Removed extraneous dbxml-perl-db46-build.patch (Fedora 7 only)

* Thu Jan 03 2008 Milan Zazrivec <mzazrivec@redhat.com> 2.003-1
- Minor spec file modification

* Thu Jan 03 2008 Milan Zazrivec <mzazrivec@redhat.com> 2.003-0
- Initial packaging (split from dbxml-2.3.10-9)
