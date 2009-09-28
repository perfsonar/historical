#!/bin/sh

rm -frd ~/rpmbuild/BUILD/NetAddr-IP*
rm -frd ~/rpmbuild/SOURCES/NetAddr-IP*
rm -frd ~/rpmbuild/tmp/*
rm -frd ~/rpmbuild/RPMS/noarch/perl-NetAddr-IP*
rm -frd ~/rpmbuild/SRPMS/perl-NetAddr-IP*

wget -c http://search.cpan.org/CPAN/authors/id/M/MI/MIKER/NetAddr-IP-4.027.tar.gz
tar -zvxf NetAddr-IP-4.027.tar.gz
rm -f NetAddr-IP-4.027.tar.gz
mkdir NetAddr-IP-4.027/scripts
cp perl-NetAddr-IP_post.sh NetAddr-IP-4.027/scripts
chmod +w NetAddr-IP-4.027/MANIFEST 
echo "scripts/perl-NetAddr-IP_post.sh" >> NetAddr-IP-4.027/MANIFEST 
tar -zvcf NetAddr-IP-4.027.tar.gz NetAddr-IP-4.027
rm -frd NetAddr-IP-4.027
mv NetAddr-IP-4.027.tar.gz ~/rpmbuild/SOURCES
rpmbuild -ba --sign perl-NetAddr-IP.spec
