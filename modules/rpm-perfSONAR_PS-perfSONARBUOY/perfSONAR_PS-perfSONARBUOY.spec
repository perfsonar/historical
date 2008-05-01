Name:           perfSONAR_PS-perfSONARBUOY
Version:        0.09
Release:        1%{?dist}
Summary:        perfSONARBUOY Measurement Archive
License:        distributable, see LICENSE
Group:          Development/Libraries
Source0:        perfSONAR_PS-perfSONARBUOY.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
#BuildRequires:  perl(PAR::Packer)
#BuildRequires:  perl(CGI)
#BuildRequires:  perl(CGI::Ajax)
#BuildRequires:  perl(Class::Accessor)
#BuildRequires:  perl(Config::General)

# Disable stripping the binary since it makes PAR binaries inoperable
%define __os_install_post /usr/lib/rpm/brp-compress

%define daemon_prefix    /opt/perfsonar
%define daemon_conf_dir  %{daemon_prefix}/etc
%define daemon_conf_file  %{daemon_conf_dir}/perfsonarbuoy-daemon.conf
%define daemon_var_dir   %{daemon_prefix}/var
%define daemon_bin_dir   %{daemon_prefix}/bin

%description
The perfSONAR_PS::Services::MA::perfSONARBUOY module allows one to make
BWCTL data available from backend SQL storage using the perfSONAR
perfSONARBUOY MA protocols.

%prep
%setup -q -n perfSONAR_PS-perfSONARBUOY

%build
sh build.sh

%install
awk "{gsub(/^PIDDIR=.*/,\"PIDDIR=%{daemon_var_dir}\"); gsub(/^PSB_EXE=.*/,\"PSB_EXE=%{daemon_bin_dir}/perfsonarbuoy\"); gsub(/^PSB_CONF=.*/,\"PSB_CONF=%{daemon_conf_dir}/perfsonarbuoy.conf\");; gsub(/^PSB_LOGGER=.*/,\"PSB_LOGGER=%{daemon_conf_dir}/perfsonarbuoy-logger.conf\"); print}" perfsonarbuoy.init > perfsonarbuoy.new
mv perfsonarbuoy.new perfsonarbuoy.init

mkdir -p %{buildroot}/%{daemon_bin_dir}
mkdir -p %{buildroot}/%{daemon_var_dir}
mkdir -p %{buildroot}/%{daemon_conf_dir}

install -p -m755 perfsonarbuoy %{buildroot}/%{daemon_bin_dir}
install -p -m644 logger.conf %{buildroot}/%{daemon_conf_dir}/perfsonarbuoy-logger.conf
mkdir -p %{buildroot}/etc/init.d/
install -p -m755 perfsonarbuoy.init %{buildroot}/etc/init.d/perfsonarbuoy
#%clean

%files
%defattr(-,root,root,-)
%doc Changes LICENSE README doc/Functional_Specification.doc doc/Installation_Actions_Specification.doc doc/Interface_Specification.doc
%{daemon_bin_dir}/*
%{daemon_conf_dir}/*
/etc/init.d/*

%changelog
* Thu Apr 29 2008 aaron@internet2.edu 0.09-1
- Initial specfile
