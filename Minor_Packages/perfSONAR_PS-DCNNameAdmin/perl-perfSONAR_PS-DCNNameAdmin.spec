%define _unpackaged_files_terminate_build      0
%define install_base /opt/perfsonar_ps/DCNNameAdmin

# cron/apache entry are located in the 'scripts' directory
%define crontab DCNNameAdmin_backup.cron
%define apacheconf DCNNameAdmin_apache.conf

%define relnum 1
%define disttag pSPS

Name:           perl-perfSONAR_PS-DCNNameAdmin
Version:        3.1
Release:        %{relnum}.%{disttag}
Summary:        perfSONAR_PS DCN Name Admin
License:        distributable, see LICENSE
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/perfSONAR_PS-DCNNameAdmin
Source0:        perfSONAR_PS-DCNNameAdmin-%{version}.%{relnum}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
Requires:		perl(AnyEvent) >= 4.81
Requires:		perl(AnyEvent::HTTP)
Requires:		perl(CGI)
Requires:		perl(CGI::Carp)
Requires:		perl(Config::General)
Requires:		perl(Data::Dumper)
Requires:		perl(Data::Validate::Domain)
Requires:		perl(Data::Validate::IP)
Requires:		perl(Date::Manip)
Requires:		perl(Digest::MD5)
Requires:		perl(Exporter)
Requires:		perl(Getopt::Long)
Requires:		perl(HTML::Template)
Requires:		perl(IO::File)
Requires:		perl(LWP::Simple)
Requires:		perl(LWP::UserAgent)
Requires:		perl(Log::Log4perl)
Requires:		perl(Net::CIDR)
Requires:		perl(Net::IPv6Addr)
Requires:		perl(Params::Validate)
Requires:		perl(Time::HiRes)
Requires:		perl(Time::Local)
Requires:		perl(XML::LibXML) >= 1.60
#Requires:       perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))
Requires:       perl
Requires:       httpd
%description
The DCN Name Admin package is a web-based GUI for adding the so-called friendly names to the perfSONAR Information Services (IS).

%pre

%prep
%setup -q -n perfSONAR_PS-DCNNameAdmin-%{version}.%{relnum}

%build

%install
rm -rf $RPM_BUILD_ROOT

make ROOTPATH=$RPM_BUILD_ROOT/%{install_base} rpminstall

mkdir -p $RPM_BUILD_ROOT/etc/cron.d

awk "{gsub(/^PREFIX=.*/,\"PREFIX=%{install_base}\"); print}" scripts/%{crontab} > scripts/%{crontab}.new
install -D -m 600 scripts/%{crontab}.new $RPM_BUILD_ROOT/etc/cron.d/%{crontab}

mkdir -p $RPM_BUILD_ROOT/etc/httpd/conf.d

awk "{gsub(/^PREFIX=.*/,\"PREFIX=%{install_base}\"); print}" scripts/%{apacheconf} > scripts/%{apacheconf}.new
install -D -m 644 scripts/%{apacheconf}.new $RPM_BUILD_ROOT/etc/httpd/conf.d/%{apacheconf}

%post
/etc/init.d/crond restart
/etc/init.d/httpd restart

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(0644,perfsonar,perfsonar,0755)
%doc %{install_base}/doc/*
%config %{install_base}/etc/*
%attr(0755,perfsonar,perfsonar) %{install_base}/bin/*
%attr(0755,perfsonar,perfsonar) %{install_base}/cgi-bin/*
%attr(0755,perfsonar,perfsonar) %{install_base}/scripts/*
%{install_base}/lib/*
%attr(0644,root,root) /etc/cron.d/*
/etc/httpd/conf.d/*

%changelog
* Thu Apr 15 2010 aaron@internet2.edu 3.1-1
- Initial release as an RPM
