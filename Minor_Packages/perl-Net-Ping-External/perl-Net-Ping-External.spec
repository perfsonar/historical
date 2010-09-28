Name:           perl-Net-Ping-External
Version:        0.12
Release:        1%{?dist}
Summary:        Cross-platform interface to ICMP "ping" utilities
License:        GPL+ or Artistic
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/Net-Ping-External/
Source0:        http://www.cpan.org/modules/by-module/Net/Net-Ping-External-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
BuildRequires:  perl(ExtUtils::MakeMaker)
Requires:       perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))

%description
Net::Ping::External is a module which interfaces with the "ping" command on
many systems. It presently provides a single function, ping(), that takes
in a hostname and (optionally) a timeout and returns true if the host is
alive, and false otherwise. Unless you have the ability (and willingness)
to run your scripts as the superuser on your system, this module will
probably provide more accurate results than Net::Ping will.

%prep
%setup -q -n Net-Ping-External-%{version}

%build
%{__perl} Makefile.PL INSTALLDIRS=vendor
make %{?_smp_mflags}

%install
rm -rf $RPM_BUILD_ROOT

make pure_install PERL_INSTALL_ROOT=$RPM_BUILD_ROOT

find $RPM_BUILD_ROOT -type f -name .packlist -exec rm -f {} \;
find $RPM_BUILD_ROOT -depth -type d -exec rmdir {} 2>/dev/null \;

%{_fixperms} $RPM_BUILD_ROOT/*

for i in Changes README ToDo; do
    sed -i 's/\r//' "$i"
done

%check
%{?_with_network_tests: make test }

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%doc Changes README ToDo
%{perl_vendorlib}/*
%{_mandir}/man3/*

%changelog
* Wed Jul 30 2008 Miloslav Trmač <mitr@redhat.com> 0.12-1
- Initial package.
