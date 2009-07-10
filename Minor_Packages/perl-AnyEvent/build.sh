#!/bin/sh

rm -frd ~/rpmbuild/BUILD/AnyEvent*
rm -frd ~/rpmbuild/SOURCES/AnyEvent*
rm -frd ~/rpmbuild/tmp/*
rm -frd ~/rpmbuild/RPMS/noarch/perl-AnyEvent*
rm -frd ~/rpmbuild/SRPMS/perl-AnyEvent*

wget -c http://search.cpan.org/CPAN/authors/id/M/ML/MLEHMANN/AnyEvent-4.81.tar.gz
tar -zvxf AnyEvent-4.81.tar.gz
rm -f AnyEvent-4.81.tar.gz
mkdir AnyEvent-4.81/scripts
cp perl-AnyEvent_post.sh AnyEvent-4.81/scripts
chmod +w AnyEvent-4.81/MANIFEST 
echo "scripts/perl-AnyEvent_post.sh" >> AnyEvent-4.81/MANIFEST 
tar -zvcf AnyEvent-4.81.tar.gz AnyEvent-4.81
rm -frd AnyEvent-4.81
mv AnyEvent-4.81.tar.gz ~/rpmbuild/SOURCES
rpmbuild -ba --sign perl-AnyEvent.spec
