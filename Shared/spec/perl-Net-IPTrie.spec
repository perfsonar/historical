%{!?perl_prefix: %define perl_prefix %(eval "`%{__perl} -V:installprefix`"; echo $installprefix)}
%{!?perl_style: %define perl_style %(eval "`%{__perl} -V:installstyle`"; echo $installstyle)}

Name:           perl-Net-IPTrie
Version:        0.4
Release:        1%{?dist}
Summary:        Perl module for building IPv4 and IPv6 address space hierarchies fast
License:        GPL+ or Artistic
Group:          Development/Libraries
URL:            http://search.cpan.org/dist/Net-IPTrie/
Source0:        http://www.cpan.org/modules/by-module/Net/Net-IPTrie-v%{version}.tar.gz
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:      noarch
Requires:       perl(Class::Struct) >= 0.63
Requires:       perl(NetAddr::IP) >= 4.007
Requires:       perl(Test::Simple)
Requires:       perl

%description
This module uses a radix tree (or trie) to quickly build the hierarchy of a
given address space (both IPv4 and IPv6).  This allows the user to perform
fast subnet or routing lookups. It is implemented exclusively in Perl.

%prep
%setup -q -n Net-IPTrie-v%{version}

%build
%{__perl} Build.PL install_base=/usr
./Build

%install
rm -rf $RPM_BUILD_ROOT

./Build install destdir=$RPM_BUILD_ROOT create_packlist=0
find $RPM_BUILD_ROOT -depth -type d -exec rmdir {} 2>/dev/null \;

%{_fixperms} $RPM_BUILD_ROOT/*

%check || :
./Build test

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%doc README
/usr/*

%post
ln -s %{perl_prefix}/%{perl_style}/Net %{perl_prefix}/%{perl_style}/vendor_perl

%changelog
* Wed Mar 04 2009 Jason Zurawski 0.4-1
- Specfile autogenerated by cpanspec 1.77.
