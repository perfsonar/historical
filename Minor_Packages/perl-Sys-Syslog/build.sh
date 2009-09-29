#!/bin/sh

rm -frd ~/rpmbuild/BUILD/Sys-Syslog*
rm -frd ~/rpmbuild/SOURCES/Sys-Syslog*
rm -frd ~/rpmbuild/tmp/*
rm -frd ~/rpmbuild/RPMS/noarch/perl-Sys-Syslog*
rm -frd ~/rpmbuild/RPMS/i386/perl-Sys-Syslog*
rm -frd ~/rpmbuild/RPMS/x86_64/perl-Sys-Syslog*
rm -frd ~/rpmbuild/SRPMS/perl-Sys-Syslog*

wget -c http://search.cpan.org/CPAN/authors/id/S/SA/SAPER/Sys-Syslog-0.27.tar.gz
tar -zvxf Sys-Syslog-0.27.tar.gz
rm -f Sys-Syslog-0.27.tar.gz
mkdir Sys-Syslog-0.27/scripts
cp perl-Sys-Syslog_post.sh Sys-Syslog-0.27/scripts
chmod +w Sys-Syslog-0.27/MANIFEST 
echo "scripts/perl-Sys-Syslog_post.sh" >> Sys-Syslog-0.27/MANIFEST 
tar -zvcf Sys-Syslog-0.27.tar.gz Sys-Syslog-0.27
rm -frd Sys-Syslog-0.27
mv Sys-Syslog-0.27.tar.gz ~/rpmbuild/SOURCES
rpmbuild -ba --sign perl-Sys-Syslog.spec
