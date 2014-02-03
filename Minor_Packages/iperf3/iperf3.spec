Name:			iperf3
Version:		3.0b6
Release:		4%{?dist}
Summary:		Measurement tool for TCP/UDP bandwidth performance
License:		BSD
Group:			Applications/Internet
URL:			http://code.google.com/p/iperf/
Source0:		http://iperf.googlecode.com/files/iperf-%{version}.tar.gz
BuildRoot:		%{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildRequires:	libuuid-devel

%description
Iperf is a tool to measure maximum TCP bandwidth, allowing the tuning of
various parameters and UDP characteristics. Iperf reports bandwidth, delay
jitter, data-gram loss. Iperf3 is a new implementation from scratch, with
the goal of a smaller, simpler code base, and a library version of the
functionality that can be used in other programs. Iperf3 is not backwards
compatible with Iperf2.x.

%prep
%setup -q -n iperf-%{version}

%build
%configure
make %{?_smp_mflags}

%install
rm -rf %{buildroot}
%makeinstall -C src INSTALL_DIR="%{buildroot}%{_bindir}"
mkdir -p %{buildroot}%{_mandir}/man1
#mv %{buildroot}%{_mandir}/man1/iperf3.1 %{buildroot}%{_mandir}/man1/iperf3.1
rm %{buildroot}/usr/include/iperf_*.h
rm %{buildroot}%{_libdir}/libiperf.a

%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root,-)
%doc AUTHORS README INSTALL TODO
%{_mandir}/man1/iperf3.1.gz
%{_mandir}/man3/libiperf.3.gz
%{_bindir}/iperf3


%changelog

* Fri Apr 16 2013 Andy Lake <andy@es.net> - 3.0b5-1
- Rebuilt latest version

* Fri Oct 12 2012 Andrew Sides <asides@es.net> - 3.0b4-2
- Rebuilt for CentOS

* Wed Apr 06 2011 G.Balaji <balajig81@gmail.com> 3.0b4-2
- Changed the Spec name, removed static libs generation and devel package.

* Sat Mar 26 2011 G.Balaji <balajig81@gmail.com> 3.0b4-1
- Initial Version
