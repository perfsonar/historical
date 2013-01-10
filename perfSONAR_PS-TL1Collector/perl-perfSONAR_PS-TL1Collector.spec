%define install_base /opt/perfsonar_ps/tl1_service

# init scripts must be located in the 'scripts' directory
%define init_script_1 perfsonar-tl1-service
%define init_script_2 perfsonar-tl1-collector

%define relnum 1
%define disttag pSPS

Name:           perl-perfSONAR_PS-TL1Collector
Version:        3.3
Release:        %{relnum}.%{disttag}
Summary:        perfSONAR-PS TL1 Collector/Service
License:        distributable, see LICENSE
Group:          Development/Libraries
URL:            http://www.internet2.edu/performance/pS-PS/
Source0:        perfSONAR_PS-TL1Collector-%{version}.%{relnum}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
Requires:	perl(Carp)
Requires:	perl(Config::General)
Requires:	perl(Cwd)
Requires:	perl(DBI)
Requires:	perl(Data::Dumper)
Requires:	perl(Data::UUID)
Requires:	perl(Date::Manip)
Requires:	perl(Digest::MD5)
Requires:	perl(English)
Requires:	perl(Error)
Requires:	perl(Exporter)
Requires:	perl(Fcntl)
Requires:	perl(File::Basename)
Requires:	perl(FindBin)
Requires:	perl(Getopt::Long)
Requires:	perl(HTTP::Daemon)
Requires:	perl(IO::File)
Requires:	perl(LWP::Simple)
Requires:	perl(LWP::UserAgent)
Requires:	perl(Log::Log4perl)
Requires:	perl(Module::Load)
Requires:	perl(Net::DNS)
Requires:	perl(Net::Ping)
Requires:	perl(Net::SNMP)
Requires:	perl(Net::Telnet)
Requires:	perl(NetAddr::IP)
Requires:	perl(POSIX)
Requires:	perl(Params::Validate)
Requires:	perl(RRDp)
Requires:	perl(Regexp::Common)
Requires:	perl(Storable)
Requires:	perl(Time::HiRes)
Requires:	perl(XML::LibXML)
Requires:	perl(base)
Requires:	perl(lib)
Requires:	perl(warnings)
Requires:       perl

%description
The perfSONAR-PS TL1Collector Service is capable of collecting and storing the
TL1 counters from network devices.  This service comes packaged with a
collector that is capable of gathering this information.  The data is stored in
SQL capable databases.  

%pre
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -r -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep
%setup -q -n perfSONAR_PS-TL1Collector-%{version}.%{relnum}

%build

%install
rm -rf $RPM_BUILD_ROOT

make ROOTPATH=$RPM_BUILD_ROOT/%{install_base} install

mkdir -p $RPM_BUILD_ROOT/etc/init.d

awk "{gsub(/^ROOTPATH=.*/,\"ROOTPATH=%{install_base}\"); print}" scripts/%{init_script_1} > scripts/%{init_script_1}.new
install -m 755 scripts/%{init_script_1}.new $RPM_BUILD_ROOT/etc/init.d/%{init_script_1}

awk "{gsub(/^ROOTPATH=.*/,\"ROOTPATH=%{install_base}\"); print}" scripts/%{init_script_2} > scripts/%{init_script_2}.new
install -m 755 scripts/%{init_script_2}.new $RPM_BUILD_ROOT/etc/init.d/%{init_script_2}

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(0644,perfsonar,perfsonar,0755)
%doc %{install_base}/doc/*
%config %{install_base}/etc/*
%attr(0755,perfsonar,perfsonar) %{install_base}/bin/*
%attr(0755,perfsonar,perfsonar) %{install_base}/scripts/*
%{install_base}/lib/*
%attr(0755,perfsonar,perfsonar) /etc/init.d/*

%post
mkdir -p /var/log/perfsonar
chown perfsonar:perfsonar /var/log/perfsonar

mkdir -p /var/run/perfSONAR/tl1_collector
chown perfsonar:perfsonar /var/run/perfSONAR/tl1_collector

mkdir -p /var/lib/perfsonar/tl1_collector/data

%{install_base}/scripts/createMetadataDB --config %{install_base}/etc/collector.conf

chown -R perfsonar:perfsonar /var/lib/perfsonar/tl1_collector

/sbin/chkconfig --add %{init_script_1}
/sbin/chkconfig --add %{init_script_2}

%preun
if [ "$1" = "0" ]; then
    # Totally removing the service
    /etc/init.d/%{init_script_1} stop
    /sbin/chkconfig --del %{init_script_1}
    /etc/init.d/%{init_script_2} stop
    /sbin/chkconfig --del %{init_script_2}
fi

%postun
if [ "$1" != "0" ]; then
    # An RPM upgrade
    /etc/init.d/%{init_script_1} restart
    /etc/init.d/%{init_script_2} restart
fi

%changelog
* Wed Oct 01 2009 aaron@internet2.edu 3.1-1
- Initial spec file
