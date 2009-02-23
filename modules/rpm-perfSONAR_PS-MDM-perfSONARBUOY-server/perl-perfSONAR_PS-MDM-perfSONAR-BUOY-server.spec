%define install_base /usr/lib/perfsonar/services/perfSONAR-BUOY/server

# init scripts must be located in the 'scripts' directory
%define init_script_1 pSB.sh
%define init_script_2 pSB_collector.sh

Name:           perl-perfSONAR_PS-MDM-perfSONAR-BUOY-server
Version:        0.10
Release:        5%{?dist}
Summary:        perfSONAR_PS MDM perfSONAR-BUOY Measurement Archive and Collection System
License:        distributable, see LICENSE
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/perfSONAR_PS-perfSONAR-BUOY/
Source0:        perfSONAR_PS-MDM-perfSONAR-BUOY-server.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
Requires:		perl(Config::General)
Requires:		perl(Carp)
Requires:		perl(Cwd)
Requires:		perl(DBI)
Requires:		perl(DB_File)
Requires:		perl(Data::UUID)
Requires:		perl(Date::Manip)
Requires:		perl(Digest::MD5)
Requires:		perl(English)
Requires:		perl(Error)
Requires:		perl(Exporter)
Requires:		perl(Fcntl)
Requires:		perl(File::Basename)
Requires:		perl(File::Path)
Requires:		perl(File::Temp)
Requires:		perl(FileHandle)
Requires:		perl(FindBin)
Requires:		perl(Getopt::Long)
Requires:		perl(Getopt::Std)
Requires:		perl(HTTP::Daemon)
Requires:		perl(IO::File)
Requires:		perl(IO::Socket)
Requires:		perl(LWP::Simple)
Requires:		perl(LWP::UserAgent)
Requires:		perl(Log::Log4perl)
Requires:		perl(Math::BigFloat)
Requires:		perl(Math::BigInt)
Requires:		perl(Module::Load)
Requires:		perl(Net::Ping)
Requires:		perl(POSIX)
Requires:		perl(Params::Validate)
Requires:		perl(Socket)
Requires:		perl(Sys::Hostname)
Requires:		perl(Sys::Syslog)
Requires:		perl(Term::ReadKey)
Requires:		perl(Time::HiRes)
Requires:		perl(XML::LibXML)
#Requires:       perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))
Requires:       perl
Requires:	    perl-DBD-MySQL
Requires:	    mysql-server
Requires:	    libdbi-dbd-mysql
Requires:       perl-perfSONAR_PS-MDM-perfSONAR-BUOY-config

%description
perfSONAR-BUOY is a scheduled bandwidth testing framework, storage system, and querable web service.  The server program contains the items required to gather, store, and deliver the periodic measurements initiated by a the related client package.  

%pre
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep
%setup -q -n perfSONAR_PS-MDM-perfSONAR-BUOY-server

%build

%install
rm -rf $RPM_BUILD_ROOT

make ROOTPATH=$RPM_BUILD_ROOT/%{install_base} install

mkdir -p $RPM_BUILD_ROOT/etc/init.d

awk "{gsub(/^PREFIX=.*/,\"PREFIX=%{install_base}\"); print}" scripts/%{init_script_1} > scripts/%{init_script_1}.new
install -m 755 scripts/%{init_script_1}.new $RPM_BUILD_ROOT/etc/init.d/%{init_script_1}

awk "{gsub(/^PREFIX=.*/,\"PREFIX=%{install_base}\"); print}" scripts/%{init_script_2} > scripts/%{init_script_2}.new
install -m 755 scripts/%{init_script_2}.new $RPM_BUILD_ROOT/etc/init.d/%{init_script_2}

mkdir -p $RPM_BUILD_ROOT/etc/perfSONAR-BUOY
ln -s %{install_base}/etc/pSB_MA.conf $RPM_BUILD_ROOT/etc/perfSONAR-BUOY/pSB_MA.conf
ln -s %{install_base}/etc/pSB_MA_logger.conf $RPM_BUILD_ROOT/etc/perfSONAR-BUOY/pSB_MA_logger.conf

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,perfsonar,perfsonar,-)
%doc %{install_base}/doc/*
%config(noreplace) %{install_base}/etc/*
%config(noreplace) /etc/perfSONAR-BUOY/*
%{install_base}/bin/*
%{install_base}/scripts/*
%{install_base}/lib/*
/etc/init.d/*

%post
mkdir -p /var/run/perfSONAR-BUOY
chown perfsonar:perfsonar /var/run/perfSONAR-BUOY
mkdir -p /var/lib/perfSONAR-BUOY
mkdir -p /var/lib/perfSONAR-BUOY/bwctl
chown -R perfsonar:perfsonar /var/lib/perfSONAR-BUOY
touch /var/log/perfSONARBUOY.log
chown perfsonar:perfsonar /var/log/perfSONARBUOY.log
chown -R perfsonar:perfsonar /etc/perfSONAR-BUOY

%changelog
* Mon Feb 23 2009 zurawski@internet2.edu 0.10.5
- Fixing bug in bwmaster.

* Tue Jan 13 2009 zurawski@internet2.edu 0.10.4
- Fixing bug in bwcollector.

* Mon Jan 7 2009 zurawski@internet2.edu 0.10.3
- Re-Branding for the MDM release

* Mon Jan 5 2009 zurawski@internet2.edu 0.10.2
- Adding Perl Deps

* Thu Dec 18 2008 zurawski@internet2.edu 0.10.1
- Initial file specification
