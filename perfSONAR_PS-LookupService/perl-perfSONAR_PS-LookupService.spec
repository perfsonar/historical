%define _unpackaged_files_terminate_build      0
%define install_base /opt/perfsonar_ps/lookup_service

# init scripts must be located in the 'scripts' directory
%define init_script_1 lookup_service

%define disttag pSPS

Name:           perl-perfSONAR_PS-LookupService
Version:        3.1
Release:        1.%{disttag}
Summary:        perfSONAR_PS Lookup Service
License:        distributable, see LICENSE
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/perfSONAR_PS-LookupService/
Source0:        perfSONAR_PS-LookupService-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
Requires:		perl(Config::General)
Requires:		perl(Data::UUID)
Requires:		perl(Data::Validate::IP)
Requires:		perl(Digest::MD5)
Requires:		perl(English)
Requires:		perl(Error)
Requires:		perl(File::Basename)
Requires:		perl(File::Temp)
Requires:		perl(File::stat)
Requires:		perl(Getopt::Long)
Requires:		perl(HTTP::Daemon)
Requires:		perl(Hash::Merge)
Requires:		perl(IO::File)
Requires:		perl(LWP::Simple)
Requires:		perl(LWP::UserAgent)
Requires:		perl(Log::Log4perl)
Requires:		perl(Module::Load)
Requires:		perl(Net::CIDR)
Requires:		perl(Net::IPTrie)
Requires:		perl(Net::IPv6Addr)
Requires:		perl(Net::Ping)
Requires:		perl(Params::Validate)
Requires:		perl(Sys::Hostname)
Requires:		perl(Time::HiRes)
Requires:		perl(XML::LibXML) >= 1.60
#Requires:       perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))
Requires:       perl
Requires:       dbxml

%description
The perfSONAR-PS Lookup Service can function in one of two roles: global root or home lookup service.  Please read the documentation for instructions.  

%pre
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep
%setup -q -n perfSONAR_PS-LookupService

%build

%install
rm -rf $RPM_BUILD_ROOT

make ROOTPATH=$RPM_BUILD_ROOT/%{install_base} install

mkdir -p $RPM_BUILD_ROOT/etc/init.d

awk "{gsub(/^PREFIX=.*/,\"PREFIX=%{install_base}\"); print}" scripts/%{init_script_1} > scripts/%{init_script_1}.new
install -D -m 755 scripts/%{init_script_1}.new $RPM_BUILD_ROOT/etc/init.d/%{init_script_1}

%post
mkdir -p /var/log/perfsonar
chown perfsonar:perfsonar /var/log/perfsonar

mkdir -p /var/lib/perfsonar/lookup_service/xmldb
if [ ! -f /var/lib/perfsonar/lookup_service/xmldb/DB_CONFIG ]; then
	%{install_base}/scripts/psCreateLookupDB --directory /var/lib/perfsonar/lookup_service/xmldb
fi
chown -R perfsonar:perfsonar /var/lib/perfsonar

/sbin/chkconfig --add lookup_service

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,perfsonar,perfsonar,-)
%doc %{install_base}/doc/*
%config %{install_base}/etc/*
%{install_base}/bin/*
%{install_base}/scripts/*
%{install_base}/lib/*
/etc/init.d/*

%preun
if [ $1 -eq 0 ]; then
    /sbin/chkconfig --del lookup_service
    /sbin/service lookup_service stop
fi

%changelog
* Thu Mar 12 2009 zurawski@internet2.edu 3.1-1
- Initial release as an RPM

