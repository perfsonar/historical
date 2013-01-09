%define _unpackaged_files_terminate_build      0
%define install_base /opt/SimpleLS/bootstrap

%define relnum 0
%define disttag pSPS

Name:           perl-perfSONAR_PS-SimpleLS-BootStrap
Version:        3.3
Release:        %{relnum}.%{disttag}
Summary:        perfSONAR_PS SimpleLS BootStrap
License:        distributable, see LICENSE
Group:          Development/Libraries
Source0:        perfSONAR_PS-SimpleLS-BootStrap-%{version}.%{relnum}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch

Requires:               perl(FindBin)
Requires:               perl(Getopt::Long)
Requires:               perl(JSON)
Requires:               perl(LWP)
Requires:               perl(LWP::Simple)
Requires:               perl(Net::Ping)
Requires:               perl(Params::Validate)
Requires:               perl(Time::HiRes)
Requires:               perl(URI)
Requires:               perl(YAML::Syck)
Requires:               perl(DateTime::Format::ISO8601)
Requires:       perl
Requires:       coreutils
Requires:       shadow-utils
Requires:       chkconfig

%description
The perfSONAR_PS SimpleLS BootStrap is used to monitor/retrieve currently active Simple LS nodes.

%pre
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -r -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep
%setup -q -n perfSONAR_PS-SimpleLS-BootStrap-%{version}.%{relnum}

%build

%install
rm -rf $RPM_BUILD_ROOT

make ROOTPATH=$RPM_BUILD_ROOT/%{install_base} rpminstall


%post
mkdir -p /var/log/SimpleLS/bootstrap
chown perfsonar:perfsonar /var/log/SimpleLS/bootstrap


%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,perfsonar,perfsonar,-)
%config %{install_base}/etc/*
%attr(0755,perfsonar,perfsonar) %{install_base}/bin/*
%attr(0755,perfsonar,perfsonar) %{install_base}/lib/*
%{install_base}/doc/*
