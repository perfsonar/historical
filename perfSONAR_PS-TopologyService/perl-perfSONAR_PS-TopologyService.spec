%define install_base /opt/perfsonar_ps/topology_service

# init scripts must be located in the 'scripts' directory
%define init_script_1 topology_service

%define relnum 1
%define disttag pSPS

Name:			perl-perfSONAR_PS-TopologyService
Version:		3.3
Release:		%{relnum}.%{disttag}
Summary:		perfSONAR_PS Topology Service
License:		Distributable, see LICENSE
Group:			Development/Libraries
URL:			http://psps.perfsonar.net/topology/
Source0:		perfSONAR_PS-TopologyService-%{version}.%{relnum}.tar.gz
BuildRoot:		%{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:		noarch
Requires:		perl(Carp)
Requires:		perl(Config::General)
Requires:		perl(Cwd)
Requires:		perl(Data::Dumper)
Requires:		perl(Data::UUID)
Requires:		perl(Digest::MD5)
Requires:		perl(English)
Requires:		perl(Error)
Requires:		perl(Exporter)
Requires:		perl(Fcntl)
Requires:		perl(File::Basename)
Requires:		perl(FindBin)
Requires:		perl(Getopt::Long)
Requires:		perl(HTTP::Daemon)
Requires:		perl(IO::File)
Requires:		perl(LWP::Simple)
Requires:		perl(LWP::UserAgent)
Requires:		perl(Log::Log4perl)
Requires:		perl(Module::Load)
Requires:		perl(Net::Ping)
Requires:		perl(POSIX)
Requires:		perl(Params::Validate)
Requires:		perl(Sleepycat::DbXml)
Requires:		perl(Time::HiRes)
Requires:		perl(XML::LibXML) >= 1.61
Requires:		perl(base)
Requires:		perl(lib)
Requires:		perl(warnings)

%description
The perfSONAR-PS Topology Service delivers stored topology information when
queried.

%pre
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -r -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep
%setup -q -n perfSONAR_PS-TopologyService-%{version}.%{relnum}

%build

%install
rm -rf %{buildroot}

make ROOTPATH=%{buildroot}/%{install_base} install

mkdir -p %{buildroot}/etc/init.d

awk "{gsub(/^PREFIX=.*/,\"PREFIX=%{install_base}\"); print}" scripts/%{init_script_1} > scripts/%{init_script_1}.new
install -D -m 0755 scripts/%{init_script_1}.new %{buildroot}/etc/init.d/%{init_script_1}

%clean
rm -rf %{buildroot}

%post
mkdir -p /var/log/perfsonar
chown perfsonar:perfsonar /var/log/perfsonar

mkdir -p /var/lib/perfsonar/topology_service
if [ ! -f /var/lib/perfsonar/topology_service/DB_CONFIG ];
then
	%{install_base}/scripts/psCreateTopologyDB --directory /var/lib/perfsonar/topology_service
fi
chown -R perfsonar:perfsonar /var/lib/perfsonar

/sbin/chkconfig --add %{init_script_1}

%preun
if [ "$1" = "0" ]; then
	# Totally removing the service
	/etc/init.d/%{init_script_1} stop
	/sbin/chkconfig --del %{init_script_1}
fi

%postun
if [ "$1" != "0" ]; then
	# An RPM upgrade
	/etc/init.d/%{init_script_1} restart
fi

%files
%defattr(0644,perfsonar,perfsonar,0755)
%doc %{install_base}/doc/*
%config %{install_base}/etc/*
%attr(0755,perfsonar,perfsonar) %{install_base}/bin/*
%attr(0755,perfsonar,perfsonar) %{install_base}/scripts/*
%{install_base}/lib/*
%attr(0755,perfsonar,perfsonar) /etc/init.d/*

%changelog
* Tue Sep 22 2009 aaron@internet2.edu 3.1-3
- useradd option change
- Add script to remove elements from the database

* Thu May 29 2009 aaron@internet2.edu 3.1-2
- Documentation updates

* Wed Dec 10 2008 aaron@internet2.edu 3.1-1
- Initial service oriented spec file
