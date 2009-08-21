%define install_base /opt/perfsonar_ps/PingER-GUI
%define logging_base /var/log/perfsonar

# init script must be located in the 'script' directory
%define crontab pinger_cache.cron
%define disttag pSPS
%define apacheconf pinger_gui.conf
%define relnum 6

Name:           perl-perfSONAR_PS-PingER-GUI
Version:        3.1
Release:        %{relnum}.%{disttag}
Summary:        perfSONAR_PS PingER  data charts GUI
License:        distributable, see LICENSE
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/perfSONAR_PS-PingER-GUI/
Source0:        perfSONAR_PS-PingER-GUI-%{version}.%{relnum}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch

Requires:       perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))

Requires:       perl(DateTime) >= 0.41
Requires:       perl(DateTime::Format::Builder) >= 0.7901
Requires:       perl(Carp) >= 0.41
Requires:       perl(Carp::Clan) >= 0.41
Requires:       perl(Config::General) 
Requires:       perl(Catalyst::Runtime)
Requires:       perl(Catalyst::View::TT)
Requires:       perl(Catalyst::Plugin::StackTrace)
Requires:       perl(Catalyst::Plugin::Static::Simple)
Requires:       perl(Catalyst::Plugin::ConfigLoader)

Requires:       perl(Class::Data::Inheritable)

Requires:       perl(Class::Accessor)
Requires:       perl(Class::Fields)
Requires:       perl(aliased) >= 0
Requires:       perl(Cwd)
Requires:       perl(DBI)
Requires:       perl(DB_File)
Requires:       perl(Data::UUID)
Requires:       perl(Date::Manip)
Requires:       perl(Data::Validate::Domain)
Requires:       perl(Data::Validate::IP)

Requires:       perl(Digest::MD5)
Requires:       perl(English)
Requires:       perl(Error)
Requires:       perl(Exporter)
Requires:       perl(Fcntl)
Requires:       perl(File::Basename)
Requires:       perl(File::Path)
Requires:       perl(File::Temp)
Requires:       perl(File::Copy)
Requires:       perl(File::Slurp)
Requires:       perl(FileHandle)
Requires:       perl(FindBin)
Requires:       perl(Getopt::Long)
Requires:       perl(Getopt::Std)
Requires:       perl(HTTP::Daemon)
Requires:       perl(Hash::Merge)
Requires:       perl(IO::File)
Requires:       perl(IO::Interface)
Requires:       perl(IO::Socket)
Requires:       perl(Log::Log4perl) >= 1
Requires:       perl(LWP::Simple)
Requires:       perl(LWP::UserAgent)
Requires:       perl(Math::BigFloat)
Requires:       perl(Math::BigInt)
Requires:       perl(Module::Load)
Requires:       perl(Moose) 
Requires:       perl(Mouse) 
Requires:       perl(Net::Ping)
Requires:       perl(Net::DNS)
Requires:       perl(Net::CIDR)
Requires:       perl(Net::IPv6Addr)
Requires:       perl(Net::Domain)
Requires:       perl(NetAddr::IP)
Requires:       perl(POSIX)
Requires:       perl(Pod::Usage)
Requires:       perl(Params::Validate)
Requires:       perl(Readonly)
Requires:       perl(Regexp::Common)
Requires:       perl(Socket)
Requires:       perl(Statistics::Descriptive)
Requires:       perl(Scalar::Util)
Requires:       perl(Sys::Hostname)
Requires:       perl(Sys::Syslog)
Requires:       perl(Text::CSV_XS)
Requires:       perl(Term::ReadKey)
Requires:       perl(Time::HiRes)
Requires:       perl(Time::gmtime)
Requires:       perl(Time::Local)
Requires:       perl(JSON::XS)
Requires:       perl(XML::LibXML) >= 1.62
Requires:       perl(constant)
Requires:       perl(version) >= 0.5
Requires:       perl(fields)
Requires:       perl(aliased)
Requires:       perl(utf8)
Requires:       perl(base)
Requires:       httpd
Requires:       mod_perl2
Requires:       apache2-mpm-prefork
Requires:       libapache2-mod-perl2

%description
The perfSONAR_PS PingER data charts GUI allows one to view graphs.

%pre
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :


%prep
%setup -q -n perfSONAR_PS-PingER-GUI-%{version}.%{relnum}

%build

%install
rm -rf $RPM_BUILD_ROOT

make ROOTPATH=$RPM_BUILD_ROOT/%{install_base} install

mkdir -p $RPM_BUILD_ROOT/etc/cron.d

awk "{gsub(\"$RPM_BUILD_ROOT/\",\"\"); print}" scripts/%{crontab} > scripts/%{crontab}.new
install -m 600 scripts/%{crontab}.new  $RPM_BUILD_ROOT/etc/cron.d/%{crontab}

mkdir -p $RPM_BUILD_ROOT/etc/httpd/conf.d
  
awk "{gsub(\"$RPM_BUILD_ROOT/\",\"\"); print}" scripts/%{apacheconf} > scripts/%{apacheconf}.new
install -D -m 644 scripts/%{apacheconf}.new   $RPM_BUILD_ROOT/etc/httpd/conf.d/%{apacheconf} 
 
awk "{gsub(\"$RPM_BUILD_ROOT/\",\"\"); print}" lib/PingerGUI.pm >   lib/PingerGUI.pm.new
install -D -m 644  lib/PingerGUI.pm.new    l%{install_base}/lib/PingerGUI.pm
 
%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,perfsonar,perfsonar,-)
%doc %{install_base}/doc/*
%{install_base}/bin/*
%{install_base}/scripts/*
%{install_base}/lib/*
%{install_base}/root/*
/etc/cron.d/*
/etc/httpd/conf.d/*
%{install_base}/pinger_gui_conf.yml

%post
mkdir -p %{logging_base}
chown perfsonar:perfsonar %{logging_base}
 
mkdir -p /var/lib/perfsonar
chown -R perfsonar:perfsonar    /var/lib/perfsonar
 
chown -R apache:apache  %{install_base}/root
chown -R root:root /etc/cron.d/%{crontab} 

/etc/init.d/crond restart
/etc/init.d/httpd restart

%changelog

