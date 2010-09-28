Summary: TCP performance tuning
Name: multi-ethtool
Version: 0.1
Release: 1%{?dist}.0
License: GPLv2
Group: System Environment/Base
#URL: not available atm
Source0: multi-ethtool.init
Source1: multi-ethtool.sysconfig
Source2: COPYING
Source3: README
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root
BuildArch: noarch
Requires(post): chkconfig
Requires(preun): chkconfig
Requires: grep sed

%description
multi-ethtool provides settings for disabling/enabling certain TCP parameters
via ethtool.  See %{_sysconfdir}/sysconfig/multi-ethtool for tuning parameters.

%prep

%build

%install
rm -rf $RPM_BUILD_ROOT
install -m 755 -d $RPM_BUILD_ROOT%{_sysconfdir}/sysconfig
install -m 644 %{SOURCE1} $RPM_BUILD_ROOT%{_sysconfdir}/sysconfig/multi-ethtool
install -m 755 -d $RPM_BUILD_ROOT%{_initrddir}
install -m 755 %{SOURCE0} $RPM_BUILD_ROOT%{_initrddir}/multi-ethtool

install -m 755 -d $RPM_BUILD_ROOT%{_docdir}/%{name}-%{version}
install -m 644 %{SOURCE2} $RPM_BUILD_ROOT%{_docdir}/%{name}-%{version}
install -m 644 %{SOURCE3} $RPM_BUILD_ROOT%{_docdir}/%{name}-%{version}

install -m 755 -d $RPM_BUILD_ROOT%{_datadir}/%{name}

%clean
rm -rf $RPM_BUILD_ROOT

%post
/sbin/chkconfig --add multi-ethtool

%preun
if [ "$1" -eq 0 ]; then
	/sbin/service multi-ethtool stop >/dev/null 2>&1
	/sbin/chkconfig --del multi-ethtool
fi

%postun
if [ "$1" -eq 1 ]; then
	/sbin/service multi-ethtool condrestart >/dev/null 2>&1
fi

%files
%defattr(-,root,root,-)
%dir %attr(0755,root,root) %{_docdir}/%{name}-%{version}
%doc %attr(0644,root,root) %{_docdir}/%{name}-%{version}/COPYING
%doc %attr(0644,root,root) %{_docdir}/%{name}-%{version}/README
%attr(0755,root,root) %{_initrddir}/multi-ethtool
%config(noreplace) %attr(0644,root,root) %{_sysconfdir}/sysconfig/multi-ethtool

%changelog

* Tue Jun 29 2010 Tom Throckmorton <throck@mcnc.org>  - 0.1-1
- initial package, based loosely on ktune
