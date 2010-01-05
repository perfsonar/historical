#!/bin/sh

rm -frd ~/rpmbuild/BUILD/Math-Int64*
rm -frd ~/rpmbuild/SOURCES/Math-Int64*
rm -frd ~/rpmbuild/tmp/*
rm -frd ~/rpmbuild/RPMS/noarch/perl-Math-Int64*
rm -frd ~/rpmbuild/SRPMS/perl-Math-Int64*

wget -c http://search.cpan.org/CPAN/authors/id/S/SA/SALVA/Math-Int64-0.09.tar.gz
tar -zvxf Math-Int64-0.09.tar.gz
rm -f Math-Int64-0.09.tar.gz
mkdir Math-Int64-0.09/scripts
cp perl-Math-Int64_post.sh Math-Int64-0.09/scripts
chmod +w Math-Int64-0.09/MANIFEST 
echo "scripts/perl-Math-Int64_post.sh" >> Math-Int64-0.09/MANIFEST 
tar -zvcf Math-Int64-0.09.tar.gz Math-Int64-0.09
rm -frd Math-Int64-0.09
mv Math-Int64-0.09.tar.gz ~/rpmbuild/SOURCES
rpmbuild -ba --sign perl-Math-Int64.spec
