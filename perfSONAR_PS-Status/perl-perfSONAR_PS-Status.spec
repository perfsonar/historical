%define install_base /opt/perfsonar_ps/status

# init scripts must be located in the 'scripts' directory
%define init_script_1 perfsonar-status-service
%define init_script_2 perfsonar-status-collector

%define relnum 1
%define disttag pSPS

Name:			perl-perfSONAR_PS-Status
Version:		3.3
Release:		%{relnum}.%{disttag}
Summary:		perfSONAR-PS Status Service
License:		Distributable, see LICENSE
Group:			Development/Libraries
URL:			http://psps.perfsonar.net/status/
Source0:		perfSONAR_PS-Status-%{version}.%{relnum}.tar.gz
BuildRoot:		%{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:		noarch
Requires:		perl
Requires:		perl(Carp)
Requires:		perl(Config::General)
Requires:		perl(Cwd)
Requires:		perl(DBD::SQLite)
Requires:		perl(DBI)
Requires:		perl(Data::Dumper)
Requires:		perl(Data::UUID)
Requires:		perl(Digest::MD5)
Requires:		perl(English)
Requires:		perl(Error)
Requires:		perl(Exporter)
Requires:		perl(Fcntl)
Requires:		perl(File::Basename)
Requires:		perl(Getopt::Long)
Requires:		perl(HTTP::Daemon)
Requires:		perl(IO::File)
Requires:		perl(LWP::Simple)
Requires:		perl(LWP::UserAgent)
Requires:		perl(Log::Log4perl)
Requires:		perl(Module::Load)
Requires:		perl(Net::Ping)
Requires:		perl(Net::SNMP)
Requires:		perl(Net::Telnet)
Requires:		perl(POSIX)
Requires:		perl(Params::Validate)
Requires:		perl(Time::HiRes)
Requires:		perl(XML::LibXML) >= 1.61
Requires:		perl(base)
Requires:		perl(warnings)
Requires:		coreutils
Requires:		chkconfig
Requires:		shadow-utils
Requires:		which

%description
The perfSONAR-PS Status Service is capable of storing the historical 'status'
of network devices. This service comes packaged with a collector that is
capable of gathering this information via methods such as SNMP or custom
scripts. The data is stored in MySQL capable databases.  

%pre
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -r -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep
%setup -q -n perfSONAR_PS-Status-%{version}.%{relnum}

%build

%install
rm -rf %{buildroot}

make ROOTPATH=%{buildroot}/%{install_base} rpminstall

mkdir -p %{buildroot}/etc/init.d

awk "{gsub(/^ROOTPATH=.*/,\"ROOTPATH=%{install_base}\"); print}" scripts/%{init_script_1} > scripts/%{init_script_1}.new
install -m 0755 scripts/%{init_script_1}.new %{buildroot}/etc/init.d/%{init_script_1}

awk "{gsub(/^ROOTPATH=.*/,\"ROOTPATH=%{install_base}\"); print}" scripts/%{init_script_2} > scripts/%{init_script_2}.new
install -m 0755 scripts/%{init_script_2}.new %{buildroot}/etc/init.d/%{init_script_2}

%clean
rm -rf %{buildroot}

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

%files
%defattr(0644,perfsonar,perfsonar,0755)
%doc %{install_base}/doc/*
%config %{install_base}/etc/*
%{install_base}/dependencies
%attr(0755,perfsonar,perfsonar) %{install_base}/bin/*
%attr(0755,perfsonar,perfsonar) %{install_base}/scripts/*
%{install_base}/lib/*
%attr(0755,perfsonar,perfsonar) /etc/init.d/*

%changelog
* Tue Sep 22 2009 zurawski@internet2.edu 3.1-3
- useradd option change
- mysql fixes

* Thu May 29 2009 aaron@internet2.edu 3.1-2
- Documentation updates
- Include the client.pl script
- Fix a problem where the MA might erroneously report "unknown" states:
 - http://code.google.com/p/perfsonar-ps/issues/detail?id=150

* Wed Dec 10 2008 aaron@internet2.edu 3.1-1
- Initial service oriented spec file
