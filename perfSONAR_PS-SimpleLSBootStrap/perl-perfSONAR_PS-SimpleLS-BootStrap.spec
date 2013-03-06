%define install_base /opt/SimpleLS/bootstrap
%define init_script_server simple_ls_bootstrap_server
%define init_script_client simple_ls_bootstrap_client

%define relnum 3 
%define disttag pSPS

Name:			perl-perfSONAR_PS-SimpleLS-BootStrap
Version:		3.3
Release:		%{relnum}.%{disttag}
Summary:		perfSONAR_PS SimpleLS BootStrap
License:		Distributable, see LICENSE
Group:			Development/Libraries
Source0:		perfSONAR_PS-SimpleLS-BootStrap-%{version}.%{relnum}.tar.gz
BuildRoot:		%{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:		noarch

%description
The perfSONAR_PS SimpleLS BootStrap is used to monitor/retrieve currently
active Simple LS nodes.

%package server
Summary:		Determine and publish active list of Lookup Services
Group:			Development/Libraries
Requires:		perl(FindBin)
Requires:		perl(Getopt::Long)
Requires:		perl(JSON)
Requires:		perl(LWP)
Requires:		perl(LWP::Simple)
Requires:		perl(Net::Ping)
Requires:		perl(Params::Validate)
Requires:		perl(Time::HiRes)
Requires:		perl(URI)
Requires:		perl(YAML::Syck)
Requires:		perl(DateTime::Format::ISO8601)
Requires:		perl
Requires:		coreutils
Requires:		shadow-utils
Requires:		chkconfig

%description server
Package for host to determine and publish active list of Lookup Services.

%package client
Summary:		Determine best Simple Lookup Service
Group:			Development/Libraries
Requires:		perl(FindBin)
Requires:		perl(Getopt::Long)
Requires:		perl(JSON)
Requires:		perl(LWP)
Requires:		perl(LWP::Simple)
Requires:		perl(Net::Ping)
Requires:		perl(Params::Validate)
Requires:		perl(Time::HiRes)
Requires:		perl(URI)
Requires:		perl(YAML::Syck)
Requires:		perl(DateTime::Format::ISO8601)
Requires:		perl
Requires:		coreutils
Requires:		shadow-utils
Requires:		chkconfig

%description client
Package for host running Lookup service clients to determine best Simple Lookup
Service to use.

%pre
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -r -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep
%setup -q -n perfSONAR_PS-SimpleLS-BootStrap-%{version}.%{relnum}

%build

%install
rm -rf %{buildroot}

make ROOTPATH=%{buildroot}/%{install_base} rpminstall

mkdir -p %{buildroot}/etc/init.d

awk "{gsub(/^PREFIX=.*/,\"PREFIX=%{install_base}\"); print}" scripts/%{init_script_server} > scripts/%{init_script_server}.new
install -D -m 0755 scripts/%{init_script_server}.new %{buildroot}/etc/init.d/%{init_script_server}
awk "{gsub(/^PREFIX=.*/,\"PREFIX=%{install_base}\"); print}" scripts/%{init_script_client} > scripts/%{init_script_client}.new
install -D -m 0755 scripts/%{init_script_client}.new %{buildroot}/etc/init.d/%{init_script_client}

%post server
mkdir -p /var/log/SimpleLS
chown perfsonar:perfsonar /var/log/SimpleLS
/sbin/chkconfig --add %{init_script_server}

%post client
mkdir -p /var/log/SimpleLS
chown perfsonar:perfsonar /var/log/SimpleLS
/sbin/chkconfig --add %{init_script_client}

%clean
rm -rf %{buildroot}

%files server
%defattr(-,perfsonar,perfsonar,-)
%config %{install_base}/etc/hosts-server.yml
%config %{install_base}/etc/activehosts.json
%config %{install_base}/etc/SimpleLSBootStrapServerDaemon.conf
%config %{install_base}/etc/SimpleLSBootStrapServerDaemon-logger.conf
%attr(0755,perfsonar,perfsonar) /etc/init.d/%{init_script_server}
%attr(0755,perfsonar,perfsonar) %{install_base}/scripts/%{init_script_server}
%attr(0755,perfsonar,perfsonar) %{install_base}/bin/SimpleLSBootStrapServerDaemon.pl
%attr(0755,perfsonar,perfsonar) %{install_base}/bin/SimpleLSBootStrap.pl
%attr(0755,perfsonar,perfsonar) %{install_base}/lib/*
%{install_base}/dependencies
%{install_base}/doc/*

%files client
%defattr(-,perfsonar,perfsonar,-)
%config %{install_base}/etc/hosts-client.yml
%config %{install_base}/etc/service_url
%config %{install_base}/etc/SimpleLSBootStrapClientDaemon.conf
%config %{install_base}/etc/SimpleLSBootStrapClientDaemon-logger.conf
%attr(0755,perfsonar,perfsonar) /etc/init.d/%{init_script_client}
%attr(0755,perfsonar,perfsonar) %{install_base}/scripts/%{init_script_client}
%attr(0755,perfsonar,perfsonar) %{install_base}/bin/SimpleLSBootStrapClientDaemon.pl
%attr(0755,perfsonar,perfsonar) %{install_base}/lib/*

%changelog
* Fri Jan 11 2013 asides@es.net 3.3-1
- 3.3 beta release

* Thu Jan 10 2013 andy@es.net 3.3
- Initial RPM build
