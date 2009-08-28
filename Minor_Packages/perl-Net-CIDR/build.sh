#!/bin/sh

rm -frd ~/rpmbuild/BUILD/Net-CIDR*
rm -frd ~/rpmbuild/SOURCES/Net-CIDR*
rm -frd ~/rpmbuild/tmp/*
rm -frd ~/rpmbuild/RPMS/noarch/perl-Net-CIDR*
rm -frd ~/rpmbuild/SRPMS/perl-Net-CIDR*

wget -c http://search.cpan.org/CPAN/authors/id/M/MR/MRSAM/Net-CIDR-0.13.tar.gz
tar -zvxf Net-CIDR-0.13.tar.gz
rm -f Net-CIDR-0.13.tar.gz
mkdir Net-CIDR-0.13/scripts
cp perl-Net-CIDR_post.sh Net-CIDR-0.13/scripts
chmod +w Net-CIDR-0.13/MANIFEST 
echo "scripts/perl-Net-CIDR_post.sh" >> Net-CIDR-0.13/MANIFEST 
tar -zvcf Net-CIDR-0.13.tar.gz Net-CIDR-0.13
rm -frd Net-CIDR-0.13
mv Net-CIDR-0.13.tar.gz ~/rpmbuild/SOURCES
rpmbuild -ba --sign perl-Net-CIDR.spec
