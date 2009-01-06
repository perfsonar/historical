%define install_base /opt/perfsonar/perfSONAR-BUOY/client

# init scripts must be located in the 'scripts' directory
%define init_script_1 pSB_master.sh

Name:           perl-perfSONAR_PS-perfSONAR-BUOY-client
Version:        0.10
Release:        1%{?dist}
Summary:        perfSONAR_PS perfSONAR-BUOY Client package
License:        distributable, see LICENSE
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/perfSONAR_PS-perfSONAR-BUOY/
Source0:        perfSONAR_PS-perfSONAR-BUOY-client.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
Requires:		perl(Data::UUID)
Requires:		perl(Digest::MD5)
Requires:		perl(English)
Requires:		perl(Exporter)
Requires:		perl(Fcntl)
Requires:		perl(File::Basename)
Requires:		perl(File::Path)
Requires:		perl(FileHandle)
Requires:		perl(FindBin)
Requires:		perl(Getopt::Long)
Requires:		perl(Getopt::Std)
Requires:		perl(IO::File)
Requires:		perl(IO::Socket)
Requires:		perl(IPC::Open3)
Requires:		perl(LWP::UserAgent)
Requires:		perl(Log::Log4perl)
Requires:		perl(Params::Validate)
Requires:		perl(Socket)
Requires:		perl(Sys::Syslog)
Requires:		perl(Time::HiRes)
Requires:		perl(XML::LibXML)
#Requires:       perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))
Requires:       perl(:MODULE_COMPAT_5.8.5)
Requires:       perl-perfSONAR_PS-perfSONAR-BUOY-config

%description
perfSONAR-BUOY is a scheduled bandwidth testing framework, storage system, and querable web service.  The client program contains the component that performs scheduled tests between specified hosts.

%pre
/usr/sbin/groupadd perfsonar 2> /dev/null || :
/usr/sbin/useradd -g perfsonar -s /sbin/nologin -c "perfSONAR User" -d /tmp perfsonar 2> /dev/null || :

%prep
%setup -q -n perfSONAR_PS-perfSONAR-BUOY-client

%build

%install
rm -rf $RPM_BUILD_ROOT

make ROOTPATH=$RPM_BUILD_ROOT/%{install_base} install

mkdir -p $RPM_BUILD_ROOT/etc/init.d

awk "{gsub(/^PREFIX=.*/,\"PREFIX=%{install_base}\"); print}" scripts/%{init_script_1} > scripts/%{init_script_1}.new
install -m 755 scripts/%{init_script_1}.new $RPM_BUILD_ROOT/etc/init.d/%{init_script_1}

mkdir -p $RPM_BUILD_ROOT/etc/perfSONAR-BUOY
ln -s %{install_base}/etc/client_logger.conf $RPM_BUILD_ROOT/etc/perfSONAR-BUOY/client_logger.conf

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
chmod -R 644 /opt/perfsonar/perfSONAR-BUOY/client/etc/requests/*xml
chmod 755 /opt/perfsonar/perfSONAR-BUOY/client/etc/requests
mkdir -p /var/lib/perfSONAR-BUOY
chown -R perfsonar:perfsonar /var/lib/perfSONAR-BUOY

%changelog
* Mon Jan 5 2009 zurawski@internet2.edu 0.10.1
- Initial file specification

