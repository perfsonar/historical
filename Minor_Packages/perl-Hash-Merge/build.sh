#!/bin/sh

rm -frd ~/rpmbuild/BUILD/Hash-Merge*
rm -frd ~/rpmbuild/SOURCES/Hash-Merge*
rm -frd ~/rpmbuild/tmp/*
rm -frd ~/rpmbuild/RPMS/noarch/perl-Hash-Merge*
rm -frd ~/rpmbuild/SRPMS/perl-Hash-Merge*

wget -c http://search.cpan.org/CPAN/authors/id/D/DM/DMUEY/Hash-Merge-0.11.tar.gz
tar -zvxf Hash-Merge-0.11.tar.gz
rm -f Hash-Merge-0.11.tar.gz
mkdir Hash-Merge-0.11/scripts
cp perl-Hash-Merge_post.sh Hash-Merge-0.11/scripts
chmod +w Hash-Merge-0.11/MANIFEST 
echo "scripts/perl-Hash-Merge_post.sh" >> Hash-Merge-0.11/MANIFEST 
tar -zvcf Hash-Merge-0.11.tar.gz Hash-Merge-0.11
rm -frd Hash-Merge-0.11
mv Hash-Merge-0.11.tar.gz ~/rpmbuild/SOURCES
rpmbuild -ba --sign perl-Hash-Merge.spec
