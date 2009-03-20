%define install_base /opt/perfsonar_ps/topology_service

# init scripts must be located in the 'scripts' directory
%define init_script_1 topology_service
# %define init_script_2 ls_registration_daemon

Name:           perl-perfSONAR_PS-TopologyService
Version:        3.1
Release:        1%{?dist}
Summary:        perfSONAR_PS Topology Service
License:        distributable, see LICENSE
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/perfSONAR_PS-TopologyService/
Source0:        perfSONAR_PS-TopologyService.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
Requires:       perl(Carp)
Requires:       perl(Config::General)
Requires:       perl(Cwd)
Requires:       perl(Data::Dumper)
Requires:       perl(Data::UUID)
Requires:       perl(Digest::MD5)
Requires:       perl(English)
Requires:       perl(Error)
Requires:       perl(Exporter)
Requires:       perl(Fcntl)
Requires:       perl(File::Basename)
Requires:       perl(FindBin)
Requires:       perl(Getopt::Long)
Requires:       perl(HTTP::Daemon)
Requires:       perl(IO::File)
Requires:       perl(LWP::Simple)
Requires:       perl(LWP::UserAgent)
Requires:       perl(Log::Log4perl)
Requires:       perl(Module::Load)
Requires:       perl(Net::Ping)
Requires:       perl(POSIX)
Requires:       perl(Params::Validate)
Requires:       perl(Sleepycat::DbXml)
Requires:       perl(Time::HiRes)
Requires:       perl(XML::LibXML)
Requires:       perl(base)
Requires:       perl(lib)
Requires:       perl(warnings)

%description
The perfSONAR-PS Topology Service delivers stored topology information when queried.

%pre
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep
%setup -q -n perfSONAR_PS-TopologyService

%build

%install
rm -rf $RPM_BUILD_ROOT

make ROOTPATH=$RPM_BUILD_ROOT/%{install_base} install

mkdir -p $RPM_BUILD_ROOT/etc/init.d

awk "{gsub(/^PREFIX=.*/,\"PREFIX=%{install_base}\"); print}" scripts/%{init_script_1} > scripts/%{init_script_1}.new
install -D -m 755 scripts/%{init_script_1}.new $RPM_BUILD_ROOT/etc/init.d/%{init_script_1}

#awk "{gsub(/^PREFIX=.*/,\"PREFIX=%{install_base}\"); print}" scripts/%{init_script_2} > scripts/%{init_script_2}.new
#install -D -m 755 scripts/%{init_script_2}.new $RPM_BUILD_ROOT/etc/init.d/%{init_script_2}

%post
mkdir -p /var/log/perfsonar
chown perfsonar:perfsonar /var/log/perfsonar

mkdir -p /var/lib/perfsonar/topology_service
if [ ! -f /var/lib/perfsonar/topology_service/DB_CONFIG ];
then
	%{install_base}/scripts/psCreateTopologyDB --directory /var/lib/perfsonar/topology_service
fi
chown -R perfsonar:perfsonar /var/lib/perfsonar

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

%changelog
* Wed Dec 10 2008 aaron@internet2.edu 3.1-1
- Initial service oriented spec file
