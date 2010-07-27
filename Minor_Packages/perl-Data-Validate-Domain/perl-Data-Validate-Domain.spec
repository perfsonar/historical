%{!?perl_prefix: %define perl_prefix %(eval "`%{__perl} -V:installprefix`"; echo $installprefix)}
%{!?perl_style: %define perl_style %(eval "`%{__perl} -V:installstyle`"; echo $installstyle)}

%define disttag pSPS

Name:           perl-Data-Validate-Domain
Version:        0.09
Release:        1.%{disttag}
Summary:        Domain validation methods
License:        CHECK(GPL+ or Artistic)
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/Data-Validate-Domain/
Source0:        http://www.cpan.org/modules/by-module/Data/Data-Validate-Domain-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
Requires:       perl(Net::Domain::TLD) >= 1.62
Requires:       perl(Test::More)
Requires:       perl

%description
This module collects domain validation routines to make input validation,
and untainting easier and more readable.

%prep
%setup -q -n Data-Validate-Domain-%{version}

%build
%{__perl} Makefile.PL INSTALL_BASE=%{perl_prefix}
make %{?_smp_mflags}

%install
rm -rf $RPM_BUILD_ROOT

make pure_install PERL_INSTALL_ROOT=$RPM_BUILD_ROOT

find $RPM_BUILD_ROOT -type f -name .packlist -exec rm -f {} \;
find $RPM_BUILD_ROOT -depth -type d -exec rmdir {} 2>/dev/null \;

%{__mv} scripts $RPM_BUILD_ROOT/tmp

%{_fixperms} $RPM_BUILD_ROOT/*

%check || :
make test

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%doc Changes README
/usr/*
/tmp/*

%post
/tmp/./perl-Data-Validate-Domain_post.sh
%{__rm} /tmp/perl-Data-Validate-Domain_post.sh

%changelog
* Thu Jul 09 2009 Jason Zurawski 0.09-1
- Specfile autogenerated by cpanspec 1.78.