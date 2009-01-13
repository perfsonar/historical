%define install_base /usr/lib/perfsonar/services/perfSONAR-BUOY/config

Name:           perl-perfSONAR_PS-MDM-perfSONAR-BUOY-config
Version:        0.10
Release:        4%{?dist}
Summary:        perfSONAR_PS MDM perfSONAR-BUOY Config Package
License:        distributable, see LICENSE
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/perfSONAR_PS-perfSONAR-BUOY/
Source0:        perfSONAR_PS-MDM-perfSONAR-BUOY-config.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
#Requires:       perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))
Requires:       perl

%description
perfSONAR-BUOY is a scheduled bandwidth testing framework, storage system, and querable web service.  The config package consists of mutual configuration files to be used by the related client and server packages.

%pre
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep
%setup -q -n perfSONAR_PS-MDM-perfSONAR-BUOY-config

%build

%install
rm -rf $RPM_BUILD_ROOT

make ROOTPATH=$RPM_BUILD_ROOT/%{install_base} install

mkdir -p $RPM_BUILD_ROOT/etc/perfSONAR-BUOY
ln -s %{install_base}/etc/owmesh.conf $RPM_BUILD_ROOT/etc/perfSONAR-BUOY/owmesh.conf

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,perfsonar,perfsonar,-)
%doc %{install_base}/doc/*
%config(noreplace) %{install_base}/etc/*
%config(noreplace) /etc/perfSONAR-BUOY/*

%post
chown -R perfsonar:perfsonar /etc/perfSONAR-BUOY

%changelog
* Tue Jan 13 2009 zurawski@internet2.edu 0.10.4
- Fixing bug in bwcollector.

* Mon Jan 7 2009 zurawski@internet2.edu 0.10.3
- Re-Branding for the MDM release

* Mon Jan 5 2009 zurawski@internet2.edu 0.10.2
- Adding Perl Deps

* Thu Dec 18 2008 zurawski@internet2.edu 0.10.1
- Initial file specification
