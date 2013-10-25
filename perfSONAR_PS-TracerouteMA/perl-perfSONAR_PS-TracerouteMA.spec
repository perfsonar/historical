%define install_base /opt/perfsonar_ps/traceroute_ma

# init scripts must be located in the 'scripts' directory
%define init_script_traceroute_ma traceroute_ma
%define init_script_traceroute_master traceroute_master
%define init_script_traceroute_scheduler traceroute_scheduler
%define init_script_traceroute_mp traceroute_ondemand_mp

%define relnum 1 
%define disttag pSPS

Name:			perl-perfSONAR_PS-TracerouteMA
Version:		3.3.2
Release:		%{relnum}.%{disttag}
Summary:		perfSONAR_PS Traceroute Measurement Archive and Collection System
License:		Distributable, see LICENSE
Group:			Development/Libraries
URL:			http://search.cpan.org/dist/perfSONAR_PS-TracerouteMA/
Source0:		perfSONAR_PS-TracerouteMA-%{version}.%{relnum}.tar.gz
BuildRoot:		%{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:		noarch
Requires:		perl

%description
Traceroute MA is a framework, storage system, and querable web service for
traceroute data.

%package config
Summary:		perfSONAR_PS Traceroute MA Configuration Information
Group:			Development/Tools
%description config
The Traceroute MA config package contains a configuration file that both the
server and client packages require to operate.

%package client
Summary:		perfSONAR_PS Traceroute MPs and registration system
Group:			Applications/Communications
Requires:		perl(Carp)
Requires:		perl(Config::General)
Requires:		perl(Cwd)
Requires:		perl(Data::UUID)
Requires:		perl(Data::Validate::IP)
Requires:		perl(Digest::MD5)
Requires:		perl(English)
Requires:		perl(Error)
Requires:		perl(Exporter)
Requires:		perl(Fcntl)
Requires:		perl(File::Basename)
Requires:		perl(File::Copy)
Requires:		perl(File::Temp)
Requires:		perl(FileHandle)
Requires:		perl(Getopt::Long)
Requires:		perl(HTTP::Daemon)
Requires:		perl(IO::File)
Requires:		perl(LWP::Simple)
Requires:		perl(LWP::UserAgent)
Requires:		perl(Log::Log4perl)
Requires:		perl(Math::BigFloat)
Requires:		perl(Math::Int64)
Requires:		perl(Module::Load)
Requires:		perl(Net::Ping)
Requires:		perl(Net::Traceroute)
Requires:		perl(POSIX)
Requires:		perl(Params::Validate)
Requires:		perl(Socket)
Requires:		perl(Symbol)
Requires:		perl(Term::ReadKey)
Requires:		perl(Time::HiRes)
Requires:		perl(XML::LibXML)
Requires:		perl-perfSONAR_PS-TracerouteMA-config
Requires:		traceroute
%description client
The Traceroute MPs conists of tools that perform measurements on the beacons
as well as client applications that can interact with the web service.

%package server
Summary:		perfSONAR_PS Traceroute Measurement Archive and Collection System
Group:			Applications/Communications
Requires:		perl(Carp)
Requires:		perl(Config::General)
Requires:		perl(Cwd)
Requires:		perl(DBI)
Requires:		perl(Data::UUID)
Requires:		perl(Data::Validate::IP)
Requires:		perl(Digest::MD5)
Requires:		perl(English)
Requires:		perl(Error)
Requires:		perl(Exporter)
Requires:		perl(Fcntl)
Requires:		perl(File::Basename)
Requires:		perl(File::Copy)
Requires:		perl(File::Temp)
Requires:		perl(FileHandle)
Requires:		perl(Getopt::Long)
Requires:		perl(HTTP::Daemon)
Requires:		perl(IO::File)
Requires:		perl(LWP::Simple)
Requires:		perl(LWP::UserAgent)
Requires:		perl(Log::Log4perl)
Requires:		perl(Math::BigFloat)
Requires:		perl(Math::Int64)
Requires:		perl(Module::Load)
Requires:		perl(Net::Ping)
Requires:		perl(POSIX)
Requires:		perl(Params::Validate)
Requires:		perl(Socket)
Requires:		perl(Symbol)
Requires:		perl(Term::ReadKey)
Requires:		perl(Time::HiRes)
Requires:		perl(XML::LibXML)
Requires:		perl-DBD-MySQL
Requires:		perl-perfSONAR_PS-TracerouteMA-config
Requires:		perl-perfSONAR_PS-SimpleLS-BootStrap-client
Requires:		chkconfig
Requires:		coreutils
Requires:		initscripts
Requires:		libdbi-dbd-mysql
Requires:		mysql
Requires:		mysql-server
Requires:		shadow-utils
%description server
The Traceroute MA server consists of the tools that interact with the database
and collect measurements from local or remote beacons.

%pre config
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -r -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%pre client
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -r -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%pre server
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -r -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep
%setup -q -n perfSONAR_PS-TracerouteMA-%{version}.%{relnum}

%build

%install
rm -rf %{buildroot}

make ROOTPATH=%{buildroot}/%{install_base} rpminstall

mkdir -p %{buildroot}/etc/init.d

awk "{gsub(/^PREFIX=.*/,\"PREFIX=%{install_base}\"); print}" scripts/%{init_script_traceroute_ma} > scripts/%{init_script_traceroute_ma}.new
install -m 0755 scripts/%{init_script_traceroute_ma}.new %{buildroot}/etc/init.d/%{init_script_traceroute_ma}

awk "{gsub(/^PREFIX=.*/,\"PREFIX=%{install_base}\"); print}" scripts/%{init_script_traceroute_master} > scripts/%{init_script_traceroute_master}.new
install -m 0755 scripts/%{init_script_traceroute_master}.new %{buildroot}/etc/init.d/%{init_script_traceroute_master}

awk "{gsub(/^PREFIX=.*/,\"PREFIX=%{install_base}\"); print}" scripts/%{init_script_traceroute_scheduler} > scripts/%{init_script_traceroute_scheduler}.new
install -m 0755 scripts/%{init_script_traceroute_scheduler}.new %{buildroot}/etc/init.d/%{init_script_traceroute_scheduler}

awk "{gsub(/^PREFIX=.*/,\"PREFIX=%{install_base}\"); print}" scripts/%{init_script_traceroute_mp} > scripts/%{init_script_traceroute_mp}.new
install -m 0755 scripts/%{init_script_traceroute_mp}.new %{buildroot}/etc/init.d/%{init_script_traceroute_mp}

%clean
rm -rf %{buildroot}

%post config

%post client
mkdir -p /var/log/perfsonar
chown perfsonar:perfsonar /var/log/perfsonar

mkdir -p /var/lib/perfsonar/traceroute_ma/upload/
chown -R perfsonar:perfsonar /var/lib/perfsonar

/sbin/chkconfig --add traceroute_master
/sbin/chkconfig --add traceroute_scheduler
/sbin/chkconfig --add traceroute_ondemand_mp

%post server
mkdir -p /var/log/perfsonar
chown perfsonar:perfsonar /var/log/perfsonar

/sbin/chkconfig --add traceroute_ma

%preun client

if [ $1 -eq 0 ]; then
    /sbin/chkconfig --del traceroute_master
    /sbin/service traceroute_master stop
    /sbin/chkconfig --del traceroute_scheduler
    /sbin/service traceroute_scheduler stop
    /sbin/chkconfig --del traceroute_ondemand_mp
    /sbin/service traceroute_ondemand_mp stop
fi

%preun server
if [ $1 -eq 0 ]; then
    /sbin/chkconfig --del traceroute_ma
    /sbin/service traceroute_ma stop
fi

%files config
%defattr(-,perfsonar,perfsonar,-)
%doc %{install_base}/doc/*
%{install_base}/dependencies
%config(noreplace) %{install_base}/etc/owmesh.conf

%files client
%defattr(-,perfsonar,perfsonar,-)
%config(noreplace) %{install_base}/etc/requests
%{install_base}/bin/client.pl
%{install_base}/bin/daemon.pl
%{install_base}/bin/traceroute_master.pl
%{install_base}/bin/traceroute_scheduler.pl
%{install_base}/etc/ondemand_mp-daemon.conf
%{install_base}/etc/ondemand_mp-daemon_logger.conf
%{install_base}/etc/traceroute-master.conf
%{install_base}/etc/traceroute-master_logger.conf
%{install_base}/etc/traceroute-scheduler_logger.conf
%{install_base}/scripts/install_dependencies.sh
%{install_base}/scripts/prepare_environment_client.sh
%{install_base}/scripts/traceroute_master
%{install_base}/scripts/traceroute_scheduler
%{install_base}/scripts/traceroute_ondemand_mp
%{install_base}/lib/*
/etc/init.d/traceroute_master
/etc/init.d/traceroute_scheduler
/etc/init.d/traceroute_ondemand_mp

%files server
%defattr(-,perfsonar,perfsonar,-)
%config(noreplace) %{install_base}/etc/daemon.conf
%config(noreplace) %{install_base}/etc/daemon_logger.conf
%{install_base}/bin/clean_pSB_db.pl
%{install_base}/bin/tracedb.pl
%{install_base}/bin/daemon.pl
%{install_base}/scripts/install_dependencies.sh
%{install_base}/scripts/prepare_environment_server.sh
%{install_base}/scripts/traceroute_ma
%{install_base}/lib/*
/etc/init.d/traceroute_ma

%changelog
* Fri Jan 11 2013 asides@es.net 3.3-1
- 3.3 beta release

* Wed Oct 6 2010 andy@es.net 3.2-RC1
- Initial file specification
