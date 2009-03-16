%define _unpackaged_files_terminate_build      0
%define install_base /opt/perfsonar_ps/snmp_ma

# init scripts must be located in the 'scripts' directory
%define init_script_1 snmp_ma

Name:           perl-perfSONAR_PS-SNMPMA
Version:        3.1
Release:        1%{?dist}
Summary:        perfSONAR_PS SNMP Measurement Archive
License:        distributable, see LICENSE
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/perfSONAR_PS-SNMPMA
Source0:        perfSONAR_PS-SNMPMA.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
#Requires:		perl(Config::General)
#Requires:       perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))
Requires:       perl
Requires:       rrdtool
Requires:       rrdtool-perl

%description
The perfSONAR-PS SNMP MA is a measurement archive that is able to deliver gathered SNMP data (from tools such as Cricket/MRTG/Cacti) through a web services interface.  This particular version depends on RRDtool and related libaries to read the underlying data.    

%pre
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep
%setup -q -n perfSONAR_PS-SNMPMA

%build

%install
rm -rf $RPM_BUILD_ROOT

make ROOTPATH=$RPM_BUILD_ROOT/%{install_base} install

mkdir -p $RPM_BUILD_ROOT/etc/init.d

awk "{gsub(/^PREFIX=.*/,\"PREFIX=%{install_base}\"); print}" scripts/%{init_script_1} > scripts/%{init_script_1}.new
install -D -m 755 scripts/%{init_script_1}.new $RPM_BUILD_ROOT/etc/init.d/%{init_script_1}

%post
mkdir -p /var/log/perfsonar
chown perfsonar:perfsonar /var/log/perfsonar

mkdir -p /var/lib/perfsonar/snmp_ma
if [ ! -f /var/lib/perfsonar/snmp_ma/store.xml ];
then
	%{install_base}/scripts/makeStore.pl /var/lib/perfsonar/snmp_ma 1
fi
chown -R perfsonar:perfsonar /var/lib/perfsonar

/sbin/chkconfig --add snmp_ma

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,perfsonar,perfsonar,-)
%doc %{install_base}/doc/*
%config %{install_base}/etc/*
%{install_base}/bin/*
%{install_base}/scripts/*
%{install_base}/lib/*
/etc/init.d/*

%preun
if [ $1 -eq 0 ]; then
    /sbin/chkconfig --del snmp_ma
    /sbin/service snmp_ma stop
fi

%changelog
* Mon Mar 16 2009 zurawski@internet2.edu 3.1-1
- Initial release as an RPM

