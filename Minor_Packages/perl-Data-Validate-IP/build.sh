#!/bin/sh

rm -frd ~/rpmbuild/BUILD/Data-Validate-IP*
rm -frd ~/rpmbuild/SOURCES/Data-Validate-IP*
rm -frd ~/rpmbuild/tmp/*
rm -frd ~/rpmbuild/RPMS/noarch/perl-Data-Validate-IP*
rm -frd ~/rpmbuild/SRPMS/perl-Data-Validate-IP*

wget -c http://search.cpan.org/CPAN/authors/id/N/NE/NEELY/Data-Validate-IP-0.08.tar.gz
tar -zvxf Data-Validate-IP-0.08.tar.gz
rm -f Data-Validate-IP-0.08.tar.gz
mkdir Data-Validate-IP-0.08/scripts
cp perl-Data-Validate-IP_post.sh Data-Validate-IP-0.08/scripts
chmod +w Data-Validate-IP-0.08/MANIFEST 
echo "scripts/perl-Data-Validate-IP_post.sh" >> Data-Validate-IP-0.08/MANIFEST 
tar -zvcf Data-Validate-IP-0.08.tar.gz Data-Validate-IP-0.08
rm -frd Data-Validate-IP-0.08
mv Data-Validate-IP-0.08.tar.gz ~/rpmbuild/SOURCES
rpmbuild -ba --sign perl-Data-Validate-IP.spec
