Name:           perfSONAR_PS-SNMP
Version:        0.09
Release:        1%{?dist}
Summary:        SNMP Measurement Archive
License:        distributable, see LICENSE
Group:          Development/Libraries
Source0:        perfSONAR_PS-SNMP.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
#BuildRequires:  perl(PAR::Packer)
#BuildRequires:  perl(CGI)
#BuildRequires:  perl(CGI::Ajax)
#BuildRequires:  perl(Class::Accessor)
#BuildRequires:  perl(Config::General)

# Disable stripping the binary since it makes PAR binaries inoperable
%define __os_install_post /usr/lib/rpm/brp-compress

%define daemon_prefix    /opt/perfsonar
%define daemon_log_dir  %{daemon_prefix}/log
%define daemon_conf_dir  %{daemon_prefix}/etc
%define daemon_conf_filename  perfsonar-snmp.conf
%define daemon_conf_file  %{daemon_conf_dir}/%{daemon_conf_filename}
%define daemon_var_dir   %{daemon_prefix}/var
%define daemon_bin_dir   %{daemon_prefix}/bin

%description
The perfSONAR_PS::Services::MA::SNMP module allows one to make
BWCTL data available from backend SQL storage using the perfSONAR
SNMP MA protocols.

%prep
rm -rf %{buildroot}
%setup -q -n perfSONAR_PS-SNMP
# edit the default path in the configuration tool
awk "{gsub(/XXX_CONFFILE_XXX/,\"%{daemon_conf_filename}\"); sub(/XXX_CONFDIR_XXX/,\"%{daemon_conf_dir}\"); print}" psConfigureSNMP.perl > psConfigureSNMP.perl.new
perl -i -p -e "s/was_installed = 0/was_installed = 1/" psConfigureSNMP.perl.new
mv psConfigureSNMP.perl.new psConfigureSNMP.perl

%build
sh build.sh
pp -M RRDp -M File::Temp -M Module::Load -M Sys::Hostname -M Class::Accessor -M CGI -M CGI::Ajax -M Config::General -o psConfigureSNMP psConfigureSNMP.perl

%install
# edit the paths in the init scripts
awk "{gsub(/^PIDDIR=.*/,\"PIDDIR=%{daemon_var_dir}\"); gsub(/^PSB_EXE=.*/,\"PSB_EXE=%{daemon_bin_dir}/perfsonar-snmp\"); gsub(/^PSB_CONF=.*/,\"PSB_CONF=%{daemon_conf_dir}/perfsonar-snmp.conf\");; gsub(/^PSB_LOGGER=.*/,\"PSB_LOGGER=%{daemon_conf_dir}/perfsonar-snmp-logger.conf\"); print}" perfsonar-snmp.init > perfsonar-snmp.new
mv perfsonar-snmp.new perfsonar-snmp.init

mkdir -p %{buildroot}/%{daemon_bin_dir}
mkdir -p %{buildroot}/%{daemon_var_dir}
mkdir -p %{buildroot}/%{daemon_conf_dir}
mkdir -p %{buildroot}/%{daemon_log_dir}

install -p -m755 perfsonar-snmp %{buildroot}/%{daemon_bin_dir}
install -p -m755 psConfigureSNMP %{buildroot}/%{daemon_bin_dir}
install -p -m644 perfsonar-snmp-logger.conf %{buildroot}/%{daemon_conf_dir}/perfsonar-snmp-logger.conf
mkdir -p %{buildroot}/etc/init.d/
install -p -m755 perfsonar-snmp.init %{buildroot}/etc/init.d/perfsonar-snmp
#%clean

%files
%defattr(-,root,root,-)
%doc Changes LICENSE README
%{daemon_bin_dir}/*
%{daemon_conf_dir}/*
/etc/init.d/*

%preun
/etc/init.d/perfsonar-snmp stop

%changelog
* Thu Apr 29 2008 aaron@internet2.edu 0.09-1
- Initial specfile
