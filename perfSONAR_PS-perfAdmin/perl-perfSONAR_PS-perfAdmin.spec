%define _unpackaged_files_terminate_build      0
%define install_base /opt/perfsonar_ps/perfAdmin

%define disttag pSPS

Name:           perl-perfSONAR_PS-perfAdmin
Version:        3.1
Release:        1.%{disttag}
Summary:        perfSONAR_PS perfAdmin
License:        distributable, see LICENSE
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/perfSONAR_PS-perfAdmin
Source0:        perfSONAR_PS-perfAdmin-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
Requires:		perl(AnyEvent)
Requires:		perl(AnyEvent::HTTP)
Requires:		perl(CGI)
Requires:		perl(CGI::Carp)
Requires:		perl(Data::Dumper)
Requires:		perl(Data::Validate::Domain)
Requires:		perl(Data::Validate::IP)
Requires:		perl(Date::Manip)
Requires:		perl(Digest::MD5)
Requires:		perl(Exporter)
Requires:		perl(Getopt::Long)
Requires:		perl(HTML::Template)
Requires:		perl(IO::File)
Requires:		perl(LWP::Simple)
Requires:		perl(LWP::UserAgent)
Requires:		perl(Log::Log4perl)
Requires:		perl(Net::CIDR)
Requires:		perl(Net::IPv6Addr)
Requires:		perl(Params::Validate)
Requires:		perl(Time::HiRes)
Requires:		perl(XML::LibXML) >= 1.60
#Requires:       perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))
Requires:       perl
Requires:       httpd
%description
The perfSONAR-PS perfAdmin package is a series of simple web-based GUIs that interact with the perfSONAR Information Services (IS) to locate and display remote datasets.

%pre
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep
%setup -q -n perfSONAR_PS-perfAdmin

%build

%install
rm -rf $RPM_BUILD_ROOT

make ROOTPATH=$RPM_BUILD_ROOT/%{install_base} install

%post
mkdir -p /var/log/perfsonar
chown perfsonar:perfsonar /var/log/perfsonar

mkdir -p /var/lib/perfsonar/perfAdmin/cache
chown -R perfsonar:perfsonar /var/lib/perfsonar/perfAdmin

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,perfsonar,perfsonar,-)
%doc %{install_base}/doc/*
%config %{install_base}/etc/*
%{install_base}/bin/*
%{install_base}/scripts/*
%{install_base}/lib/*

%changelog
* Thu Jul 9 2009 zurawski@internet2.edu 3.1-1
- Initial release as an RPM

