#!/bin/sh

rm -frd ~/rpmbuild/BUILD/AnyEvent-HTTP*
rm -frd ~/rpmbuild/SOURCES/AnyEvent-HTTP*
rm -frd ~/rpmbuild/tmp/*
rm -frd ~/rpmbuild/RPMS/noarch/perl-AnyEvent-HTTP*
rm -frd ~/rpmbuild/SRPMS/perl-AnyEvent-HTTP*

wget -c http://search.cpan.org/CPAN/authors/id/M/ML/MLEHMANN/AnyEvent-HTTP-1.4.tar.gz
tar -zvxf AnyEvent-HTTP-1.4.tar.gz
rm -f AnyEvent-HTTP-1.4.tar.gz
mkdir AnyEvent-HTTP-1.4/scripts
cp perl-AnyEvent-HTTP_post.sh AnyEvent-HTTP-1.4/scripts
chmod +w AnyEvent-HTTP-1.4/MANIFEST 
echo "scripts/perl-AnyEvent-HTTP_post.sh" >> AnyEvent-HTTP-1.4/MANIFEST 
tar -zvcf AnyEvent-HTTP-1.4.tar.gz AnyEvent-HTTP-1.4
rm -frd AnyEvent-HTTP-1.4
mv AnyEvent-HTTP-1.4.tar.gz ~/rpmbuild/SOURCES
rpmbuild -ba --sign perl-AnyEvent-HTTP.spec
