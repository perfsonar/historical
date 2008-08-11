Name:           perfSONAR_PS-Status
Version:        0.09
Release:        3%{?dist}
Summary:        Status Measurement Archive
License:        distributable, see LICENSE
Group:          Development/Libraries
Source0:        perfSONAR_PS-Status.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
#BuildRequires:  perl(PAR::Packer)
#BuildRequires:  perl(CGI)
#BuildRequires:  perl(CGI::Ajax)
#BuildRequires:  perl(Class::Accessor)
#BuildRequires:  perl(Config::General)

# Disable stripping the binary since it makes PAR binaries inoperable
%define __os_install_post /usr/lib/rpm/brp-compress

%define perfsonar_prefix                /opt/perfsonar
%define perfsonar_conf_dir              %{perfsonar_prefix}/etc
%define daemon_conf_filename            linkstatus-service.conf
%define daemon_conf_file                %{perfsonar_conf_dir}/%{daemon_conf_filename}
%define daemon_logger_conf_filename     linkstatus-service-logger.conf
%define daemon_logger_conf_file         %{perfsonar_conf_dir}/%{daemon_logger_conf_filename}
%define collector_conf_filename         linkstatus-collector.conf
%define collector_conf_file             %{perfsonar_conf_dir}/%{collector_conf_filename}
%define collector_logger_conf_filename  linkstatus-collector-logger.conf
%define collector_logger_conf_file      %{perfsonar_conf_dir}/%{collector_logger_conf_filename}
%define perfsonar_var_dir               %{perfsonar_prefix}/var
%define perfsonar_log_dir               %{perfsonar_prefix}/log
%define perfsonar_bin_dir               %{perfsonar_prefix}/bin

%define elements_conf_file              %{perfsonar_conf_dir}/elements.conf
%define e2emon_compat_file              %{perfsonar_conf_dir}/e2emon_compat.conf

%description
The perfSONAR_PS Link Status service allows one to collect to and make link or
circuit status information available from SQL storage using perfSONAR Status MA
protocols.

%prep
rm -rf %{buildroot}
%setup -q -n perfSONAR_PS-Status

# edit the default path in the service configuration tool
awk "{gsub(/XXX_CONFFILE_XXX/,\"%{daemon_conf_filename}\"); sub(/XXX_CONFDIR_XXX/,\"%{perfsonar_conf_dir}\"); print}" psConfigureLinkStatus.pl > psConfigureLinkStatus.pl.new
perl -i -p -e "s/was_installed = 0/was_installed = 1/" psConfigureLinkStatus.pl.new
mv psConfigureLinkStatus.pl.new psConfigureLinkStatus.pl

# edit the default path in the collector configuration tool
awk "{gsub(/XXX_CONFFILE_XXX/,\"%{collector_conf_filename}\"); sub(/XXX_CONFDIR_XXX/,\"%{perfsonar_conf_dir}\"); print}" psConfigureLinkStatusCollector.pl > psConfigureLinkStatusCollector.pl.new
perl -i -p -e "s/was_installed = 0/was_installed = 1/" psConfigureLinkStatusCollector.pl.new
mv psConfigureLinkStatusCollector.pl.new psConfigureLinkStatusCollector.pl

%build
sh build_collector.sh
sh build_service.sh
pp -M RRDp -M File::Temp -M Module::Load -M Sys::Hostname -M Class::Accessor -M CGI -M CGI::Ajax -M Config::General -o psConfigureLinkStatus psConfigureLinkStatus.pl
pp -M RRDp -M File::Temp -M Module::Load -M Sys::Hostname -M Class::Accessor -M CGI -M CGI::Ajax -M Config::General -o psConfigureLinkStatusCollector psConfigureLinkStatusCollector.pl

%install
# edit the paths in the init scripts
awk "{gsub(/^PIDDIR=.*/,\"PIDDIR=%{perfsonar_var_dir}\"); gsub(/^STATUS_EXE=.*/,\"STATUS_EXE=%{perfsonar_bin_dir}/perfsonar-linkstatus\"); gsub(/^STATUS_CONF=.*/,\"STATUS_CONF=%{daemon_conf_file}\");; gsub(/^STATUS_LOGGER=.*/,\"STATUS_LOGGER=%{daemon_logger_conf_file}\"); print}" perfsonar-linkstatus.init > perfsonar-linkstatus.new
mv perfsonar-linkstatus.new perfsonar-linkstatus.init

awk "{gsub(/^PIDDIR=.*/,\"PIDDIR=%{perfsonar_var_dir}\"); gsub(/^STATUSCOLLECTOR_EXE=.*/,\"STATUSCOLLECTOR_EXE=%{perfsonar_bin_dir}/perfsonar-linkstatus-collector\"); gsub(/^STATUSCOLLECTOR_CONF=.*/,\"STATUSCOLLECTOR_CONF=%{collector_conf_file}\");; gsub(/^STATUSCOLLECTOR_LOGGER=.*/,\"STATUSCOLLECTOR_LOGGER=%{collector_logger_conf_file}\"); print}" perfsonar-linkstatus-collector.init > perfsonar-linkstatus-collector.new
mv perfsonar-linkstatus-collector.new perfsonar-linkstatus-collector.init

mkdir -p %{buildroot}/%{perfsonar_bin_dir}
mkdir -p %{buildroot}/%{perfsonar_var_dir}
mkdir -p %{buildroot}/%{perfsonar_log_dir}
mkdir -p %{buildroot}/%{perfsonar_conf_dir}

install -p -m755 perfsonar-linkstatus %{buildroot}/%{perfsonar_bin_dir}
install -p -m755 perfsonar-linkstatus-collector %{buildroot}/%{perfsonar_bin_dir}
install -p -m755 psConfigureLinkStatus %{buildroot}/%{perfsonar_bin_dir}
install -p -m755 psConfigureLinkStatusCollector %{buildroot}/%{perfsonar_bin_dir}
install -p -m644 linkstatus-service-logger.conf %{buildroot}/%{daemon_logger_conf_file}
install -p -m644 linkstatus-collector-logger.conf %{buildroot}/%{collector_logger_conf_file}
install -p -m644 elements.conf %{buildroot}/%{elements_conf_file}
install -p -m644 e2emon_compat.conf %{buildroot}/%{e2emon_compat_file}
mkdir -p %{buildroot}/etc/init.d/
install -p -m755 perfsonar-linkstatus-collector.init %{buildroot}/etc/init.d/perfsonar-linkstatus-collector
install -p -m755 perfsonar-linkstatus.init %{buildroot}/etc/init.d/perfsonar-linkstatus
#%clean

%files
%defattr(-,root,root,-)
%doc Changes LICENSE README
%{perfsonar_bin_dir}/*
%config %{elements_conf_file}
%config %{e2emon_compat_file}
%config %{collector_logger_conf_file}
%config %{daemon_logger_conf_file}
/etc/init.d/*

%preun
/etc/init.d/perfsonar-linkstatus stop
/etc/init.d/perfsonar-linkstatus-collector stop

%changelog
* Thu Apr 29 2008 aaron@internet2.edu 0.09-1
- Initial specfile
