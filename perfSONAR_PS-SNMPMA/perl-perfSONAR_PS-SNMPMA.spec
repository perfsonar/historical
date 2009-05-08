%define _unpackaged_files_terminate_build      0
Autoreq: 0 

%define install_base /opt/perfsonar_ps/snmp_ma

# init scripts must be located in the 'scripts' directory
%define init_script_1 snmp_ma

%define disttag pSPS

Name:           perl-perfSONAR_PS-SNMPMA
Version:        3.1
Release:        3.%{disttag}
Summary:        perfSONAR_PS SNMP Measurement Archive
License:        distributable, see LICENSE
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/perfSONAR_PS-SNMPMA
Source0:        perfSONAR_PS-SNMPMA-%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
Requires:		perl(Compress::Zlib)
Requires:		perl(Config::General)
Requires:		perl(Cwd)
Requires:		perl(DBI)
Requires:		perl(Date::Format)
Requires:		perl(Date::Parse)
Requires:		perl(Data::UUID)
Requires:		perl(Date::Manip)
Requires:		perl(Digest::MD5)
Requires:		perl(Email::Date::Format)
Requires:		perl(Error)
Requires:		perl(Error::Simple)
Requires:		perl(Exporter)
Requires:		perl(File::Basename)
Requires:		perl(File::Temp)
Requires:		perl(Getopt::Long)
Requires:		perl(HTML::Entities)
Requires:		perl(HTML::Tagset)
Requires:		perl(HTTP::Daemon)
Requires:		perl(IO::File)
Requires:		perl(IPC::Shareable)
Requires:		perl(LWP::Simple)
Requires:		perl(LWP::UserAgent)
Requires:		perl(Log::Dispatch)
Requires:		perl(Log::Dispatch::FileRotate)
Requires:		perl(Log::Dispatch::File)
Requires:		perl(Log::Dispatch::Syslog)
Requires:		perl(Log::Dispatch::Screen)
Requires:		perl(Log::Log4perl)
Requires:		perl(Mail::Sender)
Requires:		perl(Mail::Sendmail)
Requires:		perl(Mail::Send)
Requires:		perl(MIME::Lite)
Requires:		perl(Module::Load)
Requires:		perl(Net::Daemon)
Requires:		perl(Net::Daemon::Log)
Requires:		perl(Net::Daemon::Test)
Requires:		perl(Net::Ping)
Requires:		perl(Params::Validate)
Requires:		perl(RPC::PlServer)
Requires:		perl(RPC::PlClient)
Requires:		perl(RRDp)
Requires:		perl(Sys::Hostname)
Requires:		perl(Time::HiRes)
Requires:		perl(URI)
Requires:		perl(URI::Escape)
Requires:		perl(URI::Heuristic)
Requires:		perl(URI::URL)
Requires:		perl(XML::DOM)
Requires:		perl(XML::LibXML) >= 1.60
Requires:		perl(XML::LibXML::Common)
Requires:		perl(XML::NamespaceSupport)
Requires:		perl(XML::RegExp)
Requires:		perl(XML::SAX::DocumentLocator)
Requires:		perl(XML::SAX::Base)
Requires:		perl(XML::SAX::Exception)
#Requires:       perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))
Requires:       perl
Requires:		rrdtool
Requires:		rrdtool-perl

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
* Thur May 16 2009 zurawski@internet2.edu 3.1-3
- Bugfix to include the makeDBConf script

* Tues Apr 21 2009 zurawski@internet2.edu 3.1-2
- Bugfix to the RRD.pm library

* Mon Mar 16 2009 zurawski@internet2.edu 3.1-1
- Initial release as an RPM

