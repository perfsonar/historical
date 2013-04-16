Name:		        xplot-tcptrace	
Version:		0.90.7
Release:		1%{?dist}
Summary:		TCP packet tarce visualization tool. Patched for tcptrace.
License:		BSD
Group:			Applications/Internet
URL:		        http://www.xplot.org
Source0:		http://www.tcptrace.org/useful/xplot.tar.gz
BuildRoot:		%{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildRequires:          libX11-devel


%description
The program xplot was written in the late 1980s to support the analysis of TCP packet traces. This version is patched to support tcptrace.

%prep
%setup -q -n xplot

%build
%configure
make %{?_smp_mflags}

%install
rm -rf %{buildroot}
%makeinstall INSTALL_DIR="%{buildroot}%{_bindir}"

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root,-)
%{_bindir}/tcpdump2xplot
%{_bindir}/xplot
%{_mandir}/tcpdump2xplot.1
%{_mandir}/xplot.1

%changelog

* Fri Apr 16 2013 Andy Lake <andy@es.net> - 0.90.7
- Initial .spec. Target will be perfSONAR-PS Toolkit. 
