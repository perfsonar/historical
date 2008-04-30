Name:           perl-perfSONAR_PS-Web-Admin
Version:        0.09
Release:        1%{?dist}
Summary:        perfSONAR_PS Web utility for configuring perfSONAR-PS services
License:        distributable, see LICENSE
Group:          Development/Libraries
Source0:        perfSONAR_PS-Web-Admin.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
Requires:       perl(CGI)
Requires:       perl(CGI::Ajax)
Requires:       perl(Config::General)

%description
This package includes a CGI script for configuring the perfSONAR-PS daemon to
enable a perfSONARBUOY or Pinger Services.

%prep
%setup -q -n perfSONAR_PS-Web-Admin

#%build
%install
## we need to edit the files before we install them
#awk "{gsub(/^XXX_DEFAULT_XXX/,[CONF_FILENAME]); print}" perfSONAR-PS-web-admin.conf
#mv perfsonar-daemon.new perfsonar-daemon.init

#perl -i -p -e "s/was_installed = 0/was_installed = 1/" psConfigureDaemon
#awk "{gsub(/XXX_CONFDIR_XXX/,\"/etc/perfsonar\"); print}" psConfigureDaemon > psConfigureDaemon.new
#mv -f psConfigureDaemon.new p doc/Installation_Actions_Specification.doc doc/Functional_Specification.doc doc/Interface_Specification.docsConfigureDaemon
mkdir -p %{buildroot}/var/www/cgi-bin/perfSONAR-PS
install -p -m755 web-admin.cgi %{buildroot}/var/www/cgi-bin/perfSONAR-PS
mkdir -p %{buildroot}/etc/httpd/conf.d
install -p -m644 perfsonar-httpd.conf %{buildroot}/etc/httpd/conf.d/perfSONAR-PS-web-admin.conf

#%clean

%files
%defattr(-,root,root,-)
%doc Changes LICENSE README perl-perfSONAR_PS-Web-Admin.spec
/etc/httpd/conf.d/*
/var/www/cgi-bin/*

%changelog
* Thu Apr 29 2008 aaron@internet2.edu 0.09-1
- Initial specfile
