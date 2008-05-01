Name:           perfSONAR_PS-PingER-Web-Admin
Version:        0.09
Release:        1%{?dist}
Summary:        perfSONAR_PS Web utility for configuring perfSONAR-PS services
License:        distributable, see LICENSE
Group:          Development/Libraries
Source0:        perfSONAR_PS-PingER-Web-Admin.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
Requires:       perfSONAR_PS-Services-PingER
#BuildRequires:  perl(PAR::Packer)
#BuildRequires:  perl(CGI)
#BuildRequires:  perl(CGI::Ajax)
#BuildRequires:  perl(Class::Accessor)
#BuildRequires:  perl(Config::General)

# Disable stripping the binary since it makes PAR binaries inoperable
%define __os_install_post /usr/lib/rpm/brp-compress

%define daemon_conf_dir  /opt/perfsonar/etc
%define daemon_conf_file  %{daemon_conf_dir}/pinger.conf

%description
This package includes a CGI script for configuring a PingER Measurement
Archive or Measurement Point.

%prep
%setup -q -n perfSONAR_PS-PingER-Web-Admin
## we need to set the file paths
awk "{gsub(/XXX_DEFAULT_XXX/,\"%{daemon_conf_file}\"); print}" web-admin.perl.cgi > web-admin.perl.new.cgi
mv web-admin.perl.new.cgi web-admin.perl.cgi
perl -i -p -e "s/was_installed = 0/was_installed = 1/" web-admin.perl.cgi

%build
pp -M Class::Accessor -M CGI -M CGI::Ajax -M Config::General -o web-admin.cgi web-admin.perl.cgi

%install
mkdir -p %{buildroot}/var/www/cgi-bin/perfSONAR-PS
install -p -m755 web-admin.cgi %{buildroot}/var/www/cgi-bin/perfSONAR-PS/pinger-web-admin.cgi
mkdir -p %{buildroot}/etc/httpd/conf.d
install -p -m644 perfsonar-httpd.conf %{buildroot}/etc/httpd/conf.d/perfSONAR-PS-PingER-Web-Admin.conf

#%clean

%post
# ensure that the file exists
mkdir -p %{daemon_conf_dir}
touch %{daemon_conf_file}

# ensure that the web server can write it
chcon -R -t httpd_sys_script_rw_t %{daemon_conf_dir}
chgrp apache %{daemon_conf_file}
chmod 664 %{daemon_conf_file}

%files
%defattr(-,root,root,-)
%doc Changes LICENSE README perfSONAR_PS-PingER-Web-Admin.spec
/etc/httpd/conf.d/*
/var/www/cgi-bin/*

%changelog
* Thu Apr 29 2008 aaron@internet2.edu 0.09-1
- Initial specfile
