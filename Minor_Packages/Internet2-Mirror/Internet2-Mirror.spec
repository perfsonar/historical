%define _unpackaged_files_terminate_build      0
%define install_base /opt/perfsonar_ps/Internet2-Mirror

# cron/apache entry are located in the 'scripts' directory
%define crontab Internet2-Mirror.cron

%define relnum 1
%define disttag pSPS

Summary:    Internet2 Mirror Tools
Name:       Internet2-Mirror
Version:    0.1
Release:    %{relnum}.%{disttag}
License:    distributable, see http://www.internet2.edu/membership/ip.html
Group:      System Environment/Base
URL:        http://software.internet2.edu
Source0:    Internet2-Mirror-%{version}.%{relnum}.tar.gz
BuildRoot:  %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:  noarch
Requires:   yum
Requires:   rpm
Requires:   subversion

%description
Internt2 mirror package. This package contains instructions to mirror the Internet2 software repositories.  

%prep
%setup -q -n Internet2-Mirror-%{version}.%{relnum}

%build

%install
rm -rf $RPM_BUILD_ROOT

make ROOTPATH=$RPM_BUILD_ROOT/%{install_base} rpminstall

mkdir -p $RPM_BUILD_ROOT/etc/cron.d

awk "{gsub(/^PREFIX=.*/,\"PREFIX=%{install_base}\"); print}" scripts/%{crontab} > scripts/%{crontab}.new
install -D -m 600 scripts/%{crontab}.new $RPM_BUILD_ROOT/etc/cron.d/%{crontab}

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-, root, root, 0755)
%doc %{install_base}/doc/*
%{install_base}/bin/*
%{install_base}/scripts/*
/etc/cron.d/*

%post
chown -R root:root /etc/cron.d/Internet2-Mirror.cron
/etc/init.d/crond restart

%changelog
* Mon Mar 21 2011 Jason Zurawski <zurawski@internet2.edu> - 0.0.1-1
- Initial package.

