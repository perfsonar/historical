%define _unpackaged_files_terminate_build      0
%define install_base /opt/perfsonar_ps/perfsonarbuoy_ma

# init scripts must be located in the 'scripts' directory
%define init_script_ma perfsonarbuoy_ma
%define init_script_collector perfsonarbuoy_collector
%define init_script_master perfsonarbuoy_master

%define disttag pSPS

Name:           perl-perfSONAR_PS-perfSONARBUOY
Version:        3.1
Release:        1.%{disttag}
Summary:        perfSONAR_PS perfSONAR-BUOY Measurement Archive and Collection System
License:        distributable, see LICENSE
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/perfSONAR_PS-perfSONAR-BUOY/
Source0:        perfSONAR_PS-perfSONARBUOY.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
Requires:       perl
#Requires:       perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))

%description
perfSONARBUOY is a scheduled bandwidth and latency testing framework, storage system, and querable web service.

%package server
Summary:        perfSONAR_PS perfSONARBUOY Measurement Archive and Collection System
Group:          Applications/Network
Requires:		perl(Config::General)
Requires:		perl(Cwd)
Requires:		perl(DB_File)
Requires:		perl(DBI)
Requires:		perl(Data::UUID)
Requires:		perl(Date::Manip)
Requires:		perl(Digest::MD5)
Requires:		perl(Error)
Requires:		perl(Exporter)
Requires:		perl(File::Path)
Requires:		perl(File::Temp)
Requires:		perl(FileHandle)
Requires:		perl(Getopt::Long)
Requires:		perl(Getopt::Std)
Requires:		perl(HTTP::Daemon)
Requires:		perl(IO::File)
Requires:		perl(IO::Socket)
Requires:		perl(LWP::Simple)
Requires:		perl(LWP::UserAgent)
Requires:		perl(Log::Log4perl)
Requires:		perl(Math::BigFloat)
Requires:		perl(Math::BigInt)
Requires:		perl(Module::Load)
Requires:		perl(Net::Ping)
Requires:		perl(Params::Validate)
Requires:		perl(Sys::Hostname)
Requires:		perl(Sys::Syslog)
Requires:		perl(Term::ReadKey)
Requires:		perl(Time::HiRes)
Requires:		perl(XML::LibXML)
Requires:	    perl-DBD-MySQL
Requires:	    mysql
Requires:	    mysql-server
Requires:	    libdbi-dbd-mysql
Requires:       perl-perfSONAR_PS-perfSONARBUOY-config
%description server
The perfSONARBUOY server consists of the tools that interact with the database and collect measurements from local or remote beacons.

%package client
Summary:        perfSONAR_PS perfSONARBUOY Web Service Client and Measurement System
Group:          Applications/Network
Requires:		perl(Data::UUID)
Requires:		perl(Digest::MD5)
Requires:		perl(Exporter)
Requires:		perl(File::Path)
Requires:		perl(FileHandle)
Requires:		perl(Getopt::Long)
Requires:		perl(Getopt::Std)
Requires:		perl(IO::File)
Requires:		perl(IO::Socket)
Requires:		perl(IPC::Open3)
Requires:		perl(LWP::UserAgent)
Requires:		perl(Log::Log4perl)
Requires:		perl(Params::Validate)
Requires:		perl(Sys::Syslog)
Requires:		perl(Time::HiRes)
Requires:		perl(XML::LibXML)
%description client
The perfSONARBUOY client conists of tools that perform measurements on the beacons as well as client applications that can interact with the web service.

%package config
Summary:        perfSONAR_PS perfSONARBUOY Configuration Information
Group:          Applications/Network
%description config
The perfSONARBUOY config package contains a configuration file that both the server and client packages require to operate.  

%pre
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep server
%setup -q -n perfSONAR_PS-perfSONARBUOY-server

%prep client
%setup -q -n perfSONAR_PS-perfSONARBUOY-client

%prep config
%setup -q -n perfSONAR_PS-perfSONARBUOY-config

%build

%install server
rm -rf $RPM_BUILD_ROOT

make ROOTPATH=$RPM_BUILD_ROOT/%{install_base} install

mkdir -p $RPM_BUILD_ROOT/etc/init.d

awk "{gsub(/^PREFIX=.*/,\"PREFIX=%{install_base}\"); print}" scripts/%{init_script_ma} > scripts/%{init_script_ma}.new
install -m 755 scripts/%{init_script_ma}.new $RPM_BUILD_ROOT/etc/init.d/%{init_script_ma}

awk "{gsub(/^PREFIX=.*/,\"PREFIX=%{install_base}\"); print}" scripts/%{init_script_collector} > scripts/%{init_script_collector}.new
install -m 755 scripts/%{init_script_collector}.new $RPM_BUILD_ROOT/etc/init.d/%{init_script_collector}

%install client
rm -rf $RPM_BUILD_ROOT

make ROOTPATH=$RPM_BUILD_ROOT/%{install_base} install

mkdir -p $RPM_BUILD_ROOT/etc/init.d

awk "{gsub(/^PREFIX=.*/,\"PREFIX=%{install_base}\"); print}" scripts/%{init_script_master} > scripts/%{init_script_master}.new
install -m 755 scripts/%{init_script_master}.new $RPM_BUILD_ROOT/etc/init.d/%{init_script_master}

%install config
rm -rf $RPM_BUILD_ROOT

%post server
mkdir -p /var/log/perfsonar
chown perfsonar:perfsonar /var/log/perfsonar

mkdir -p /var/lib/perfsonar/perfsonarbuoy_ma
chown -R perfsonar:perfsonar /var/lib/perfsonar

/sbin/chkconfig --add perfsonarbuoy_ma
/sbin/chkconfig --add perfsonarbuoy_collector

%post client
mkdir -p /var/log/perfsonar
chown perfsonar:perfsonar /var/log/perfsonar

mkdir -p /var/lib/perfsonar/perfsonarbuoy_ma
chown -R perfsonar:perfsonar /var/lib/perfsonar

/sbin/chkconfig --add perfsonarbuoy_master

%post config

%clean
rm -rf $RPM_BUILD_ROOT

%files server
%defattr(-,perfsonar,perfsonar,-)
%doc %{install_base}/doc/*
%config(noreplace) %{install_base}/etc/daemon.conf
%config(noreplace) %{install_base}/etc/daemon_logger.conf
%{install_base}/bin/bwcollector.pl
%{install_base}/bin/configureDaemon.pl
%{install_base}/bin/makeDBConfig.pl
%{install_base}/bin/bwdb.pl
%{install_base}/bin/daemon.pl
%{install_base}/scripts/install_dependencies.sh
%{install_base}/scripts/prepare_environment_server.sh
%{install_base}/lib/*
/etc/init.d/perfsonarbuoy_ma
/etc/init.d/perfsonarbuoy_collector

%files client
%defattr(-,perfsonar,perfsonar,-)
%doc %{install_base}/doc/*
%config(noreplace) %{install_base}/etc/requests
%{install_base}/bin/client.pl
%{install_base}/bin/bwmaster.pl
%{install_base}/scripts/install_dependencies.sh
%{install_base}/scripts/prepare_environment_client.sh
%{install_base}/lib/*
/etc/init.d/perfsonarbuoy_master

%files config
%defattr(-,perfsonar,perfsonar,-)
%doc %{install_base}/doc/*
%config(noreplace) %{install_base}/etc/owmesh.conf

%preun server
if [ $1 -eq 0 ]; then
    /sbin/chkconfig --del perfsonarbuoy_ma
    /sbin/service perfsonarbuoy_ma stop
    /sbin/chkconfig --del perfsonarbuoy_collector
    /sbin/service perfsonarbuoy_collector stop
fi

%preun client

if [ $1 -eq 0 ]; then
    /sbin/chkconfig --del perfsonarbuoy_master
    /sbin/service perfsonarbuoy_master stop
fi

%changelog
* Mon Jul 13 2009 zurawski@internet2.edu 3.1-1
- Support for BWCTL and OWAMP regular testing

* Mon Feb 23 2009 zurawski@internet2.edu 0.10.4
- Fixing bug in bwmaster.

* Tue Jan 13 2009 zurawski@internet2.edu 0.10.3
- Fixing bug in bwcollector.

* Mon Jan 7 2009 zurawski@internet2.edu 0.10.2
- Adjustments to the required perl.

* Mon Jan 5 2009 zurawski@internet2.edu 0.10.1
- Initial file specification
