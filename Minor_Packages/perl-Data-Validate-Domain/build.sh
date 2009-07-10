#!/bin/sh

rm -frd ~/rpmbuild/BUILD/Data-Validate-Domain*
rm -frd ~/rpmbuild/SOURCES/Data-Validate-Domain*
rm -frd ~/rpmbuild/tmp/*
rm -frd ~/rpmbuild/RPMS/noarch/perl-Data-Validate-Domain*
rm -frd ~/rpmbuild/SRPMS/perl-Data-Validate-Domain*

wget -c http://search.cpan.org/CPAN/authors/id/N/NE/NEELY/Data-Validate-Domain-0.09.tar.gz
tar -zvxf Data-Validate-Domain-0.09.tar.gz
rm -f Data-Validate-Domain-0.09.tar.gz
mkdir Data-Validate-Domain-0.09/scripts
cp perl-Data-Validate-Domain_post.sh Data-Validate-Domain-0.09/scripts
chmod +w Data-Validate-Domain-0.09/MANIFEST 
echo "scripts/perl-Data-Validate-Domain_post.sh" >> Data-Validate-Domain-0.09/MANIFEST 
tar -zvcf Data-Validate-Domain-0.09.tar.gz Data-Validate-Domain-0.09
rm -frd Data-Validate-Domain-0.09
mv Data-Validate-Domain-0.09.tar.gz ~/rpmbuild/SOURCES
rpmbuild -ba --sign perl-Data-Validate-Domain.spec
