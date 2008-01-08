Name:           perl-perfSONAR_PS-Services-MA-SNMP
Version:        v0.01
Release:        1%{?dist}
Summary:        perfSONAR_PS::Services::MA::SNMP Perl module
License:        distributable, see LICENSE
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/perfSONAR_PS-Services-MA-SNMP/
Source0:        http://www.cpan.org/modules/by-module/perfSONAR_PS/perfSONAR_PS-Services-MA-SNMP-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
Requires:       perl(Log::Log4perl) >= 1
Requires:       perl(Module::Load) >= 0.1
Requires:       perl(perfSONAR_PS::Common) >= v0.01
Requires:       perl(perfSONAR_PS::DB::File) >= v0.01
Requires:       perl(perfSONAR_PS::DB::RRD) >= v0.01
Requires:       perl(perfSONAR_PS::DB::SQL) >= v0.01
Requires:       perl(perfSONAR_PS::Error_compat) >= v0.01
Requires:       perl(perfSONAR_PS::Messages) >= v0.01
Requires:       perl(perfSONAR_PS::Services::MA::General) >= v0.01
Requires:       perl(perfSONAR_PS::Transport) >= v0.01
Requires:       perl(perfSONAR_PS::XML::Document_string) >= v0.01
Requires:       perl(version) >= 0.5
Requires:       perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))

%description
The perfSONAR_PS::Services::MA::SNMP module allows one to make SNMP data
available in SQL or RRD files using the perfSONAR SNMP MA protocols.

%prep
%setup -q -n perfSONAR_PS-Services-MA-SNMP-%{version}

%build
%{__perl} Makefile.PL INSTALLDIRS=vendor
make %{?_smp_mflags}

%install
rm -rf $RPM_BUILD_ROOT

make pure_install PERL_INSTALL_ROOT=$RPM_BUILD_ROOT

find $RPM_BUILD_ROOT -type f -name .packlist -exec rm -f {} \;
find $RPM_BUILD_ROOT -type d -depth -exec rmdir {} 2>/dev/null \;

chmod -R u+rwX,go+rX,go-w $RPM_BUILD_ROOT/*

%check
make test

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%doc Changes LICENSE README
%{perl_vendorlib}/*
%{_mandir}/man3/*

%changelog
* Fri Jan 04 2008 aaron@internet2.edu v0.01-1
- Specfile autogenerated.
