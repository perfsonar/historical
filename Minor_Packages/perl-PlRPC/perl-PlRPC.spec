Name:       perl-PlRPC 
Version:    0.2020 
Release:    1%{?dist} 
License:    GPL+ or Artistic
Group:      Development/Libraries
Summary:    Interface for building pServer Clients 
Source:     http://search.cpan.org/CPAN/authors/id/M/MN/MNOONING/PlRPC/PlRPC-%{version}.tar.gz 
Url:        http://search.cpan.org/dist/PlRPC
BuildRoot:  %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n) 
Requires:   perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))
BuildArch:  noarch

BuildRequires: perl(ExtUtils::MakeMaker)
BuildRequires: perl(Net::Daemon) >= 0.13
BuildRequires: perl(Storable)
# tests
BuildRequires: perl(Compress::Zlib)
BuildRequires: perl(Crypt::DES)

# the better to compress you with, my dear
Requires:      perl(Compress::Zlib)
Requires:      perl(MD5)
Requires:      perl(Crypt::DES)


%description
PlRPC (Perl RPC) is a package that simplifies the writing of Perl based
client/server applications. RPC::PlServer is the package used on the
server side, and you guess what RPC::PlClient is for.  PlRPC works by 
defining a set of methods that may be executed by the client.

%prep
%setup -q -n PlRPC

%build
%{__perl} Makefile.PL INSTALLDIRS=vendor
make %{?_smp_mflags}

%install
rm -rf %{buildroot}

make pure_install PERL_INSTALL_ROOT=%{buildroot}
find %{buildroot} -type f -name .packlist -exec rm -f {} ';'
find %{buildroot} -depth -type d -exec rmdir {} 2>/dev/null ';'

%{_fixperms} %{buildroot}/*

%check
# tests fail in buildsys/mock
%{?_with_tests: make test }

%clean
rm -rf %{buildroot} 

%files
%defattr(-,root,root,-)
%doc ChangeLog README 
%{perl_vendorlib}/*
%{_mandir}/man3/*.3*

%changelog
* Wed Apr 01 2009 Chris Weyl <cweyl@alumni.drew.edu> 0.2020-1
- submission

* Thu Mar 19 2009 Chris Weyl <cweyl@alumni.drew.edu> 0.2020-0
- initial RPM packaging
- generated with cpan2dist (CPANPLUS::Dist::RPM version 0.0.8)

