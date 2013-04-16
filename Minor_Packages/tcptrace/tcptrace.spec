Name:		        tcptrace	
Version:		6.6.7
Release:		1%{?dist}
Summary:		Tool for analysis of tcpdump files
License:	        GPL	
Group:			Applications/Internet
URL:			http://www.tcptrace.org
Source0:		http://www.tcptrace.org/download/tcptrace-%{version}.tar.gz
BuildRoot:		%{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildRequires:          libpcap-devel
BuildRequires:          libnet-devel
Patch0:                 tcptrace.Makefile.patch

%description
tcptrace is a tool written by Shawn Ostermann at Ohio University, for analysis of TCP dump files. It can take as input the files produced by several popular packet-capture programs, including tcpdump, snoop, etherpeek, HP Net Metrix, and WinDump. tcptrace can produce several different types of output containing information on each connection seen, such as elapsed time, bytes and segments sent and recieved, retransmissions, round trip times, window advertisements, throughput, and more. It can also produce a number of graphs for further analysis.

%prep
%setup -q -n tcptrace-%{version}
%patch0

%build
%configure --prefix=%{buildroot} 
make %{?_smp_mflags}

%install
rm -rf %{buildroot}
#Skip make install because Makefile uses hardcoded paths. Install manually here
mkdir -p %{buildroot}/%{_bindir}
mkdir -p %{buildroot}/%{_mandir}/man1
install -m 0755 tcptrace %{buildroot}/%{_bindir}/tcptrace
install -m 0444 tcptrace.man %{buildroot}/%{_mandir}/man1/tcptrace.1

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root,-)
%{_bindir}/tcptrace
%{_mandir}/man1/tcptrace.1.gz

%changelog

* Fri Apr 16 2013 Andy Lake <andy@es.net> - 6.6.7
- Initial .spec. Target will be perfSONAR-PS Toolkit. 
