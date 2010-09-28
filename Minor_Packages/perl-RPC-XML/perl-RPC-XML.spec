%define real_name RPC-XML

Name:    perl-RPC-XML
Version: 0.64
Release: 1%{?dist}
Summary: Set of classes for core data, message and XML handling

Group:   Development/Libraries
License: Artistic 2.0 or LGPLv2
URL:     http://search.cpan.org/dist/RPC-XML/

Source0:   http://www.cpan.org/modules/by-module/RPC/%{real_name}-%{version}.tar.gz
Source1:   README.license
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n) 
BuildArch: noarch

BuildRequires: perl(ExtUtils::MakeMaker)
BuildRequires: perl(LWP)
BuildRequires: perl(Test::More)
BuildRequires: perl(XML::Parser)
# optional tests
BuildRequires: perl(Net::Server)
BuildRequires: perl(Test::Pod)
BuildRequires: perl(Test::Pod::Coverage)

%package -n perl-Apache-RPC
Summary: Companion packages for RPC::XML tuned for mod_perl environments
Group:   Development/Libraries


%description
The RPC::XML package is an implementation of XML-RPC. The module provides
classes for sample client and server implementations, a server designed as an
Apache location-handler, and a suite of data-manipulation classes that are 
used by them.

%description -n perl-Apache-RPC
This package contains Apache::RPC::Server and Apache::RPC::Status, useful for
running RPC::XML under mod_perl.


%prep
%setup -qn %{real_name}-%{version}
cp -p %{SOURCE1} .

chmod -c -x t/* 

#Filter unwanted Provides:
#  RPC::XML::Method creates two entries for some reason?
cat << \EOF > %{real_name}-prov
#!/bin/sh
%{__perl_provides} $* |\
  %{__sed} -e '/perl(RPC::XML::Method)$/d'
EOF

%define __perl_provides %{_builddir}/%{real_name}-%{version}/%{real_name}-prov
chmod +x %{__perl_provides}

%build
perl Makefile.PL INSTALLDIRS="vendor" PREFIX="%{_prefix}"
make %{?_smp_mflags}

%install
rm -rf %{buildroot}

make pure_install PERL_INSTALL_ROOT=%{buildroot}
find %{buildroot} -type f -name .packlist -exec rm -f {} ';'

%{_fixperms} %{buildroot}/*

%check
make test

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root,-)
%doc ChangeLog README etc/*.dtd README.license ex/ methods/ t/
%{_mandir}/man3/RPC*
%{_mandir}/man1/*
%{_bindir}/make_method
%{perl_vendorlib}/RPC
%{perl_vendorlib}/auto/*

%files -n perl-Apache-RPC
%defattr(-,root,root,-)
%doc README.apache2 README.license
%{_mandir}/man3/Apache*
%{perl_vendorlib}/Apache

%changelog
* Thu Oct 23 2008 Chris Weyl <cweyl@alumni.drew.edu> 0.64-1
- update to 0.64-1
- drop tests patch (fixed!)
- add BR on Net::Server

* Mon Sep 08 2008 Chris Weyl <cweyl@alumni.drew.edu> 0.60-3
- bump

* Tue Aug 26 2008 Chris Weyl <cweyl@alumni.drew.edu> 0.60-2
- quiesce offending test

* Sat Aug 23 2008 Chris Weyl <cweyl@alumni.drew.edu> 0.60-1
- even more spec cleanups :-)
- update licensing

* Fri Jul 04 2008 Chris Weyl <cweyl@alumni.drew.edu> 0.60-0.1
- update to 0.60
- spec file cleanups

* Sun Mar 16 2008 Nicholas Boyle <nsboyle@gmail.com> - 0.59-5
- Added BuildRequires for Test::More and XML::Parser

* Sun Mar 16 2008 Nicholas Boyle <nsboyle@gmail.com> - 0.59-4
- Created subpackage perl-Apache-RPC to allow RPC-XML to work without
  requiring mod_perl
- Manpages now installed as regular files, instead of docs
- Removed explicit perl_archlib and perl_vendorarch definitions

* Fri Mar 07 2008 Nicholas Boyle <nsboyle@gmail.com> - 0.59-3
- Added README.license to clarify licensing

* Sat Mar 01 2008 Nicholas Boyle <nsboyle@gmail.com> - 0.59-2
- Initial Fedora packaging

* Mon Sep 18 2006 Dries Verachtert <dries@ulyssis.org> - 0.59-1
- Updated to release 0.59.

* Wed Mar 22 2006 Dries Verachtert <dries@ulyssis.org> - 0.58-1.2
- Rebuild for Fedora Core 5.

* Wed Jun  8 2005 Dries Verachtert <dries@ulyssis.org> - 0.58-1
- Updated to release 0.58.

* Sat Jan  1 2005 Dries Verachtert <dries@ulyssis.org> - 0.57-1
- Initial package.
