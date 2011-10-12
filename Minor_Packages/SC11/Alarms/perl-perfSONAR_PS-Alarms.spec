%define _unpackaged_files_terminate_build      0
%define install_base /opt/perfsonar_ps/alarms

# cron/apache entry are located in the 'scripts' directory
%define apacheconf apache-alarms.conf

%define relnum 1
%define disttag pSPS

Name:           perl-perfSONAR_PS-Alarms
Version:        3.2
Release:        %{relnum}.%{disttag}
Summary:        perfSONAR_PS Alarms
License:        distributable, see LICENSE
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/perfSONAR_PS-Alarms
Source0:        perfSONAR_PS-Alarms-%{version}.%{relnum}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
Requires:       perl
Requires:       httpd
%description
Package to collect and store alarms collected via TL1

%pre
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -r -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep
%setup -q -n perfSONAR_PS-Alarms-%{version}.%{relnum}

%build

%install
rm -rf $RPM_BUILD_ROOT

make ROOTPATH=$RPM_BUILD_ROOT/%{install_base} rpminstall

mkdir -p $RPM_BUILD_ROOT/etc/httpd/conf.d

awk "{gsub(/^PREFIX=.*/,\"PREFIX=%{install_base}\"); print}" scripts/%{apacheconf} > scripts/%{apacheconf}.new
install -D -m 644 scripts/%{apacheconf}.new $RPM_BUILD_ROOT/etc/httpd/conf.d/%{apacheconf}

%post
mkdir -p /var/log/perfsonar
chown perfsonar:perfsonar /var/log/perfsonar

mkdir -p /var/log/perfsonar/alarms
chown perfsonar:perfsonar /var/log/perfsonar/alarms

chown apache:perfsonar /opt/perfsonar_ps/alarms/etc/alarms_cgi.conf

/etc/init.d/crond restart
/etc/init.d/httpd restart

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(0644,perfsonar,perfsonar,0755)
%config %{install_base}/etc/*
%attr(0755,perfsonar,perfsonar) %{install_base}/bin/*
%attr(0755,perfsonar,perfsonar) %{install_base}/web/*cgi
%{install_base}/web/*
%{install_base}/scripts/*
%{install_base}/lib/*
/etc/httpd/conf.d/*

%changelog
* Wed Oct 12 2011 aaron@internet2.edu 3.2-1
- Initial package
