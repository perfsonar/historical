Name:           perl-perfSONAR_PS-Services-LS
Version:        0.09
Release:        1%{?dist}
Summary:        perfSONAR_PS::Services::LS Perl module
License:        distributable, see LICENSE
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/perfSONAR_PS-Services-LS/
Source0:        http://www.cpan.org/modules/by-module/perfSONAR_PS/perfSONAR_PS-Services-LS-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
Requires:       perl(Error)
Requires:       perl(Log::Dispatch::FileRotate) >= 1
Requires:       perl(Log::Dispatch::Screen) >= 1
Requires:       perl(Log::Dispatch::Syslog) >= 1
Requires:       perl(Log::Log4perl) >= 1
Requires:       perl(Params::Validate) >= 0.64
Requires:       perl(XML::LibXML) >= 1.58
Requires:       perl(perfSONAR_PS::Common) >= 0.09
Requires:       perl(perfSONAR_PS::DB::XMLDB) >= 0.09
Requires:       perl(perfSONAR_PS::Error_compat) >= 0.09
Requires:       perl(perfSONAR_PS::Messages) >= 0.09
Requires:       perl(perfSONAR_PS::Services::Base) >= 0.09
Requires:       perl(perfSONAR_PS::Services::MA::General) >= 0.09
Requires:       perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))

%description
The perfSONAR_PS::Services::LS module allows one to run a Lookup Service where
services can register the data they contain.

%prep
%setup -q -n perfSONAR_PS-Services-LS-%{version}

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
%doc Changes LICENSE README perl-perfSONAR_PS-Services-LS.spec
%{perl_vendorlib}/*
%{_mandir}/man3/*

%changelog
* Thu Mar 27 2008 aaron@internet2.edu 0.09-1
- Specfile autogenerated.
