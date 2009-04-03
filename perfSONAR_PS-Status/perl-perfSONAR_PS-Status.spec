%define install_base /opt/perfsonar_ps/status

# init scripts must be located in the 'scripts' directory
%define init_script_1 perfsonar-status-service
%define init_script_2 perfsonar-status-collector

%define disttag pSPS

Name:           perl-perfSONAR_PS-Status
Version:        3.1
Release:        1.%{disttag}
Summary:        perfSONAR-PS Status Service
License:        distributable, see LICENSE
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/perfSONAR_PS-Status/
Source0:        perfSONAR_PS-Status.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
Requires:       perl(Carp)
Requires:       perl(Config::General)
Requires:       perl(Cwd)
Requires:       perl(DBD::SQLite)
Requires:       perl(DBI)
Requires:       perl(Data::Dumper)
Requires:       perl(Data::UUID)
Requires:       perl(Digest::MD5)
Requires:       perl(English)
Requires:       perl(Error)
Requires:       perl(Exporter)
Requires:       perl(Fcntl)
Requires:       perl(File::Basename)
Requires:       perl(Getopt::Long)
Requires:       perl(HTTP::Daemon)
Requires:       perl(IO::File)
Requires:       perl(LWP::Simple)
Requires:       perl(LWP::UserAgent)
Requires:       perl(Log::Log4perl)
Requires:       perl(Module::Load)
Requires:       perl(Net::Ping)
Requires:       perl(Net::SNMP)
Requires:       perl(Net::Telnet)
Requires:       perl(POSIX)
Requires:       perl(Params::Validate)
Requires:       perl(Time::HiRes)
Requires:       perl(XML::LibXML) >= 1.61
Requires:       perl(base)
Requires:       perl(warnings)
Requires:       perl

%description
The perfSONAR-PS Status Service is capable of storing the historical 'status' of network devices.  This service comes packaged with a collector that is capable of gathering this information via methods such as SNMP or custom scripts.  The data is stored in MySQL capable databases.  

%pre
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep
%setup -q -n perfSONAR_PS-Status

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
%defattr(0644,perfsonar,perfsonar,-)
%doc %{install_base}/doc/*
%config %{install_base}/etc/*
%attr(0755,perfsonar,perfsonar) %{install_base}/bin/*
%attr(0755,perfsonar,perfsonar) %{install_base}/scripts/*
%{install_base}/lib/*
%attr(0755,perfsonar,perfsonar) /etc/init.d/*

%post
mkdir -p /var/log/perfsonar
chown perfsonar:perfsonar /var/log/perfsonar

mkdir -p /var/lib/perfsonar
chown perfsonar:perfsonar /var/lib/perfsonar

if [ ! -f /var/lib/perfsonar/status.db ];
then
	%{install_base}/scripts/psCreateStatusDB --config %{install_base}/etc/database.conf
	chown perfsonar:perfsonar /var/lib/perfsonar/status.db
fi

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
* Wed Dec 10 2008 aaron@internet2.edu 3.1-1
- Initial service oriented spec file
