#!/bin/sh

rm -frd ~/rpmbuild/BUILD/Class-Fields*
rm -frd ~/rpmbuild/SOURCES/Class-Fields*
rm -frd ~/rpmbuild/tmp/*
rm -frd ~/rpmbuild/RPMS/noarch/perl-Class-Fields*
rm -frd ~/rpmbuild/SRPMS/perl-Class-Fields*

wget -c http://search.cpan.org/CPAN/authors/id/M/MS/MSCHWERN/Class-Fields-0.203.tar.gz
tar -zvxf Class-Fields-0.203.tar.gz
rm -f Class-Fields-0.203.tar.gz
mkdir Class-Fields-0.203/scripts
cp perl-Class-Fields_post.sh Class-Fields-0.203/scripts
chmod +w Class-Fields-0.203/MANIFEST 
echo "scripts/perl-Class-Fields_post.sh" >> Class-Fields-0.203/MANIFEST 
tar -zvcf Class-Fields-0.203.tar.gz Class-Fields-0.203
rm -frd Class-Fields-0.203
mv Class-Fields-0.203.tar.gz ~/rpmbuild/SOURCES
rpmbuild -ba --sign perl-Class-Fields.spec
