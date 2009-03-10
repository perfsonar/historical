%define install_base /opt/perfsonar_ps/topology_service

# init scripts must be located in the 'scripts' directory
%define init_script_1 topology_service
# %define init_script_2 ls_registration_daemon

Name:           perl-perfSONAR_PS-TopologyService
Version:        0.10
Release:        1%{?dist}
Summary:        perfSONAR_PS Lookup Service Registration Daemon
License:        distributable, see LICENSE
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/perfSONAR_PS-TopologyService/
Source0:        perfSONAR_PS-TopologyService.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
# XXX Add your perl requirements here. e.g.
# Requires:		perl(Config::General)
Requires:       perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))

%description
XXX ADD A DESCRIPTION OF THE PACKAGE XXX

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
if [ ! -f /var/lib/perfsonar/topology_service/DB_CONFIG ]; then
	%{install_base}/scripts/psCreateTopologyDB --directory /var/lib/perfsonar/topology_service
fi
chown -R perfsonar:perfsonar /var/lib/perfsonar

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

%changelog
* Wed Dec 10 2008 aaron@internet2.edu 0.10-1
- Initial service oriented spec file
