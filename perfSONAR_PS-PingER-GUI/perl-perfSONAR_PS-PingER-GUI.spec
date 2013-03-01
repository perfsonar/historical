%define install_base /opt/perfsonar_ps/PingER-GUI
%define logging_base /var/log/perfsonar

# init script must be located in the 'script' directory
%define crontab pinger_cache.cron
%define apacheconf pinger_gui.conf

%define relnum 2 
%define disttag pSPS

Name:			perl-perfSONAR_PS-PingER-GUI
Version:		3.3
Release:		%{relnum}.%{disttag}.%{_arch}
Summary:		perfSONAR_PS PingER  data charts GUI
License:		Distributable, see LICENSE
Group:			Development/Libraries
URL:			http://psps.perfsonar.net/pinger/
Source0:		perfSONAR_PS-PingER-GUI-%{version}.%{relnum}.%{_arch}.tar.gz
BuildRoot:		%{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
ExclusiveArch:	noarch i386 i586 i686 x86_64
Requires:		perl(aliased)
Requires:		perl(Carp) >= 0.41
Requires:		perl(Carp::Clan) >= 0.41
Requires:		perl(Catalyst::Action::RenderView)
Requires:		perl(Catalyst::Engine::Apache2::MP20)
Requires:		perl(Catalyst::Plugin::ConfigLoader)
Requires:		perl(Catalyst::Plugin::StackTrace)
Requires:		perl(Catalyst::Runtime) < 5.8
Requires:		perl(Catalyst::View::TT)
Requires:		perl(Class::Accessor)
Requires:		perl(Class::Data::Inheritable)
Requires:		perl(Class::Fields)
Requires:		perl(Config::General)
Requires:		perl(Cwd)
Requires:		perl(constant)
Requires:		perl(DBI)
Requires:		perl(DB_File)
Requires:		perl(Data::UUID)
Requires:		perl(Data::Validate::Domain)
Requires:		perl(Data::Validate::IP)
Requires:		perl(Date::Manip)
Requires:		perl(DateTime) >= 0.41
Requires:		perl(DateTime::Format::Builder) >= 0.7901
Requires:		perl(Digest::MD5)
Requires:		perl(English)
Requires:		perl(Error)
Requires:		perl(Exporter)
Requires:		perl(Fcntl)
Requires:		perl(fields)
Requires:		perl(File::Basename)
Requires:		perl(File::Copy)
Requires:		perl(File::Path)
Requires:		perl(File::Slurp)
Requires:		perl(File::Temp)
Requires:		perl(FileHandle)
Requires:		perl(FindBin)
Requires:		perl(Getopt::Long)
Requires:		perl(Getopt::Std)
Requires:		perl(HTTP::Daemon)
Requires:		perl(Hash::Merge)
Requires:		perl(IO::File)
Requires:		perl(IO::Interface)
Requires:		perl(IO::Socket)
Requires:		perl(JSON::XS)
Requires:		perl(LWP::Simple)
Requires:		perl(LWP::UserAgent)
Requires:		perl(Log::Log4perl) >= 1
Requires:		perl(Math::BigFloat)
Requires:		perl(Math::BigInt)
Requires:		perl(Module::Load)
Requires:		perl(Net::CIDR)
Requires:		perl(Net::DNS)
Requires:		perl(Net::Domain)
Requires:		perl(Net::IP)
Requires:		perl(Net::Ping)
Requires:		perl(NetAddr::IP)
Requires:		perl(POSIX)
Requires:		perl(Params::Validate)
Requires:		perl(Pod::Usage)
Requires:		perl(Readonly)
Requires:		perl(Regexp::Common)
Requires:		perl(Scalar::Util)
Requires:		perl(Socket)
Requires:		perl(Statistics::Descriptive)
Requires:		perl(Sys::Hostname)
Requires:		perl(Sys::Syslog)
Requires:		perl(Term::ReadKey)
Requires:		perl(Text::CSV_XS)
Requires:		perl(Time::HiRes)
Requires:		perl(Time::Local)
Requires:		perl(Time::gmtime)
Requires:		perl(utf8)
Requires:		perl(version) >= 0.5
Requires:		perl(XML::LibXML) >= 1.62
Requires:		perl(YAML)
Requires:		perl(base)
Requires:		httpd

%description
The perfSONAR_PS PingER data charts GUI allows one to view graphs.

%pre
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -r -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep
%setup -q -n perfSONAR_PS-PingER-GUI-%{version}.%{relnum}.%{_arch}

%build

%install
rm -rf %{buildroot}

make prefix=%{_prefix} ROOTPATH=%{buildroot}/%{install_base} install

mkdir -p %{buildroot}/etc/cron.d

awk "{gsub(\"%{buildroot}/\",\"\"); print}" scripts/%{crontab} > scripts/%{crontab}.new
install -m 0600 scripts/%{crontab}.new %{buildroot}/etc/cron.d/%{crontab}

mkdir -p %{buildroot}/etc/httpd/conf.d

awk "{gsub(\"%{buildroot}/\",\"\"); print}" scripts/%{apacheconf} > scripts/%{apacheconf}.new
install -D -m 0644 scripts/%{apacheconf}.new %{buildroot}/etc/httpd/conf.d/%{apacheconf}

awk "{gsub(\"%{buildroot}/\",\"\"); print}" lib/PingerGUI.pm > lib/PingerGUI.pm.new
awk "{gsub(\"MYPATH=/\",\"%{install_base}/\"); print}" lib/PingerGUI.pm.new > lib/PingerGUI.pm.new2
install -D -m 0644  lib/PingerGUI.pm.new2 %{buildroot}/%{install_base}/lib/PingerGUI.pm

awk "{gsub(\"MYPATH=/\",\"%{install_base}/\"); print}" pinger_gui_conf.yml > pinger_gui_conf.yml.new
install -D -m 0644 pinger_gui_conf.yml.new %{buildroot}/%{install_base}/pinger_gui_conf.yml

%clean
rm -rf %{buildroot}

%post
mkdir -p %{logging_base}
chown perfsonar:perfsonar %{logging_base}
 
mkdir -p /var/lib/perfsonar
chown -R perfsonar:perfsonar /var/lib/perfsonar
 
chown -R apache:apache %{install_base}/root
chown -R root:root /etc/cron.d/%{crontab}

%{install_base}/scripts/prep_links.sh %{install_base}

/etc/init.d/crond restart
/etc/init.d/httpd restart

%files
%defattr(-,perfsonar,perfsonar,-)
%doc %{install_base}/doc/*
%{install_base}/bin/*
%{install_base}/scripts/*
%{install_base}/lib/Catalyst/*
%{install_base}/lib/Data/*
%{install_base}/lib/perfSONAR_PS/*
%{install_base}/lib/PingerGUI/*
%{install_base}/lib/PingerGUI.pm
%{install_base}/lib/Utils.pm
%{install_base}/root/*
%{install_base}/pinger_gui_conf.yml
%{install_base}/lib/ChartDirector/lib/chartdir.lic
%{install_base}/lib/ChartDirector/lib/fonts/*
%{install_base}/lib/ChartDirector/LICENSE.TXT
%{install_base}/lib/ChartDirector/lib/perlchartdir.pm
%{install_base}/lib/ChartDirector/lib/perlchartdir5004.so
%{install_base}/lib/ChartDirector/lib/perlchartdir5005.so
%ifarch x86_64
%{install_base}/lib/ChartDirector/lib/libchartdiri64.so
%{install_base}/lib/ChartDirector/lib/libchartdirx86_64.so
%{install_base}/lib/ChartDirector/lib/perlchartdir510i64mt.so
%{install_base}/lib/ChartDirector/lib/perlchartdir510i64.so
%{install_base}/lib/ChartDirector/lib/perlchartdir58i64mt.so
%{install_base}/lib/ChartDirector/lib/perlchartdir58i64.so 
%else
%{install_base}/lib/ChartDirector/lib/libchartdiri386.so 
%{install_base}/lib/ChartDirector/lib/perlchartdir510mt.so
%{install_base}/lib/ChartDirector/lib/perlchartdir510.so
%{install_base}/lib/ChartDirector/lib/perlchartdir56mt.so
%{install_base}/lib/ChartDirector/lib/perlchartdir56.so
%{install_base}/lib/ChartDirector/lib/perlchartdir58mt.so
%{install_base}/lib/ChartDirector/lib/perlchartdir58.so
%endif
/etc/cron.d/*
/etc/httpd/conf.d/*

%changelog
* Fri Jun 22 2012 asides@es.net 3.2.2-2
- fixed possible issue occurring with i586 and i686 distributions

* Wed Aug 04 2010 maxim@fnal.gov  3.1-13
- removed deps for Moose, added modules from cpan of the correct version

* Wed Apr 28 2010 maxim@fnal.gov  3.1-12
- added dep and extra Chartdirector lib

* Tue Sep 22 2009 zurawski@internet2.edu 3.1-10
- useradd option change
