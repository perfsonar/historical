%define install_base /opt/perfsonar_ps/status

# init scripts must be located in the 'scripts' directory
%define init_script_1 perfsonar-status-service
%define init_script_2 perfsonar-status-collector

Name:           perl-perfSONAR_PS-Status
Version:        0.10
Release:        1%{?dist}
Summary:        perfSONAR_PS Lookup Service Registration Daemon
License:        distributable, see LICENSE
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/perfSONAR_PS-Status/
Source0:        perfSONAR_PS-Status.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
Requires:		perl(DBI)
Requires:		perl(DBD::SQLite)
Requires:		perl(Data::Dumper)
Requires:		perl(Digest::MD5)
Requires:		perl(English)
Requires:		perl(Exporter)
Requires:		perl(IO::File)
Requires:		perl(LWP::Simple)
Requires:		perl(LWP::UserAgent)
Requires:		perl(Log::Log4perl)
Requires:		perl(Module::Load)
Requires:		perl(Net::Ping)
Requires:		perl(Net::SNMP)
Requires:		perl(Params::Validate)
Requires:		perl(Time::HiRes)
Requires:		perl(XML::LibXML)
Requires:		perl(base)
Requires:		perl(fields)
Requires:		perl(strict)
Requires:		perl(warnings)
Requires:       perl

%description
XXX ADD A DESCRIPTION OF THE PACKAGE XXX

%pre
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep
%setup -q -n perfSONAR_PS-Status

%build

%install
rm -rf $RPM_BUILD_ROOT

make ROOTPATH=$RPM_BUILD_ROOT/%{install_base} install

mkdir -p $RPM_BUILD_ROOT/etc/init.d

awk "{gsub(/^ROOTPATH=.*/,\"ROOTPATH=%{install_base}\"); print}" scripts/%{init_script_1} > scripts/%{init_script_1}.new
install -m 755 scripts/%{init_script_1}.new $RPM_BUILD_ROOT/etc/init.d/%{init_script_1}

awk "{gsub(/^ROOTPATH=.*/,\"ROOTPATH=%{install_base}\"); print}" scripts/%{init_script_2} > scripts/%{init_script_2}.new
install -m 755 scripts/%{init_script_2}.new $RPM_BUILD_ROOT/etc/init.d/%{init_script_2}

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

%post
mkdir -p /var/log/perfsonar
chown perfsonar:perfsonar /var/log/perfsonar

mkdir -p /var/lib/perfsonar
chown perfsonar:perfsonar /var/lib/perfsonar

if [ ! -f /var/lib/perfsonar/status.db ]; then
	%{install_base}/scripts/psCreateStatusDB --type sqlite --file /var/lib/perfsonar/status.db
	chown perfsonar:perfsonar /var/lib/perfsonar/status.db
fi

%changelog
* Wed Dec 10 2008 aaron@internet2.edu 0.10-1
- Initial service oriented spec file
