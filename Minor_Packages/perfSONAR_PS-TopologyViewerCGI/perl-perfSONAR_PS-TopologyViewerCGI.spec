%define _unpackaged_files_terminate_build      0
%define install_base /opt/perfsonar_ps/topology_viewer_cgi

# cron/apache entry are located in the 'scripts' directory
%define apacheconf TopologyViewerCGI_apache.conf

%define relnum 1
%define disttag pSPS

Name:           perl-perfSONAR_PS-TopologyViewerCGI
Version:        3.1
Release:        %{relnum}.%{disttag}
Summary:        perfSONAR_PS Topology Viewer
License:        distributable, see LICENSE
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/perfSONAR_PS-TopologyViewerCGI
Source0:        perfSONAR_PS-TopologyViewerCGI-%{version}.%{relnum}.tar.gz
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
Requires:		perl(Net::IP)
Requires:		perl(Params::Validate)
Requires:		perl(Time::HiRes)
Requires:		perl(Time::Local)
Requires:		perl(XML::Tidy)
Requires:		perl(XML::LibXML) >= 1.60
#Requires:       perl(:MODULE_COMPAT_%(eval "`%{__perl} -V:version`"; echo $version))
Requires:       perl
Requires:       httpd
%description
The Topology Viewer CGI package is a web-based GUI for retrieving topology information from the perfSONAR Topology Service (TS).

%pre

%prep
%setup -q -n perfSONAR_PS-TopologyViewerCGI-%{version}.%{relnum}

%build

%install
rm -rf $RPM_BUILD_ROOT

make ROOTPATH=$RPM_BUILD_ROOT/%{install_base} rpminstall

mkdir -p $RPM_BUILD_ROOT/etc/httpd/conf.d

install -D -m 644 scripts/%{apacheconf} $RPM_BUILD_ROOT/etc/httpd/conf.d/%{apacheconf}

%post
/etc/init.d/httpd restart

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(0644,perfsonar,perfsonar,0755)
%doc %{install_base}/doc/*
%config %{install_base}/etc/*
%attr(0755,perfsonar,perfsonar) %{install_base}/cgi-bin/*
%attr(0755,perfsonar,perfsonar) %{install_base}/scripts/*
%{install_base}/lib/*
/etc/httpd/conf.d/*

%changelog
* Thu Apr 15 2010 aaron@internet2.edu 3.1-1
- Initial release as an RPM
