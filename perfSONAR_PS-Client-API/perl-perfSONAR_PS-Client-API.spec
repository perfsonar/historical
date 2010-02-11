%define _unpackaged_files_terminate_build      0
%define install_base /opt/perfsonar_ps/client_api

%define relnum 1
%define disttag pSPS

Name:           perl-perfSONAR_PS-Client-API
Version:        3.1
Release:        %{relnum}.%{disttag}
Summary:        perfSONAR_PS Client API
License:        distributable, see LICENSE
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/perfSONAR_PS-Client-API
Source0:        perfSONAR_PS-Client-API-%{version}.%{relnum}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
#Requires:		perl(AnyEvent) >= 4.81

#Requires:       perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))
Requires:       perl

%description
The perfSONAR-PS Client API package contains the libraries used to contact perfSONAR services.  Examples of how to use the API are included for reference.  

%pre
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -r -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep
%setup -q -n perfSONAR_PS-perfAdmin-%{version}.%{relnum}

%build

%install
rm -rf $RPM_BUILD_ROOT

make ROOTPATH=$RPM_BUILD_ROOT/%{install_base} rpminstall

%post
mkdir -p /var/log/perfsonar
chown perfsonar:perfsonar /var/log/perfsonar

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,perfsonar,perfsonar,-)
%doc %{install_base}/doc/*
%config %{install_base}/etc/*
%{install_base}/bin/*
%{install_base}/scripts/*
%{install_base}/lib/*

%changelog
* Wed Feb 11 2010 zurawski@internet2.edu 3.1-1
- Initial release as an RPM

