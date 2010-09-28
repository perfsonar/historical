Name:           perl-Net-Domain-TLD
Version:        1.68
Release:        1%{?dist}
Summary:        Work with TLD names
Group:          Development/Libraries
License:        GPL+ or Artistic
URL:            http://search.cpan.org/dist/Net-Domain-TLD
Source0:        http://search.cpan.org/CPAN/authors/id/A/AL/ALEXP/Net-Domain-TLD-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
BuildRequires:  perl(Test::More)
Requires:  perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))

%description
The purpose of this module is to provide user with current list of
available top level domain names including new ICANN additions and ccTLDs.

%prep
%setup -q -n Net-Domain-TLD-%{version}

%build
%{__perl} Makefile.PL INSTALLDIRS=vendor
make %{?_smp_mflags}

%install
rm -rf $RPM_BUILD_ROOT
make pure_install PERL_INSTALL_ROOT=$RPM_BUILD_ROOT
find $RPM_BUILD_ROOT -type f -name .packlist -exec rm -f {} ';'
find $RPM_BUILD_ROOT -type d -depth -exec rmdir {} 2>/dev/null ';'
chmod -R u+w $RPM_BUILD_ROOT/*

%check
make test

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%doc Changes
%{perl_vendorlib}/Net
%{_mandir}/man3/*.3*


%changelog
* Fri Mar 13 2009 Tom "spot" Callaway <tcallawa@redhat.com> - 1.68-1
- update to 1.68

* Thu Feb 26 2009 Fedora Release Engineering <rel-eng@lists.fedoraproject.org> - 1.67-4
- Rebuilt for https://fedoraproject.org/wiki/Fedora_11_Mass_Rebuild

* Wed Feb 27 2008 Tom "spot" Callaway <tcallawa@redhat.com> - 1.67-3
- Rebuild for perl 5.10 (again)

* Sun Jan 20 2008 Tom "spot" Callaway <tcallawa@redhat.com> 1.67-2
- rebuild for new perl

* Wed Dec 19 2007 Tom "spot" Callaway <tcallawa@redhat.com> 1.67-1
- 1.67

* Sun Aug 26 2007 Tom "spot" Callaway <tcallawa@redhat.com> 1.65-2
- license tag fix

* Wed Jan 17 2007 Tom "spot" Callaway <tcallawa@redhat.com> 1.65-1
- initial package for Fedora Extras
