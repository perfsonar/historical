#!/bin/sh

rm -frd ~/rpmbuild/BUILD/dbxml*
rm -frd ~/rpmbuild/SOURCES/dbxml*
rm -frd ~/rpmbuild/tmp/*
rm -frd ~/rpmbuild/RPMS/i386/dbxml*
rm -frd ~/rpmbuild/SRPMS/dbxml*

wget -c http://download.oracle.com/berkeley-db/dbxml-2.3.11.tar.gz
tar -zvxf dbxml-2.3.11.tar.gz
rm -f dbxml-2.3.11.tar.gz
patch -d dbxml-2.3.11 -p0 --verbose < dbxml-2.3.11.patch
tar -zvcf dbxml-2.3.11.tar.gz dbxml-2.3.11
rm -frd dbxml-2.3.11
mv dbxml-2.3.11.tar.gz ~/rpmbuild/SOURCES
rpmbuild -ba --sign dbxml.spec
