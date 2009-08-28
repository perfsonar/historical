#!/bin/sh

rm -frd ~/rpmbuild/BUILD/Net-IPTrie*
rm -frd ~/rpmbuild/SOURCES/Net-IPTrie*
rm -frd ~/rpmbuild/tmp/*
rm -frd ~/rpmbuild/RPMS/noarch/perl-Net-IPTrie*
rm -frd ~/rpmbuild/SRPMS/perl-Net-IPTrie*

wget -c http://search.cpan.org/CPAN/authors/id/P/PA/PAJAS/XML-LibXML-1.69.tar.gz
tar -zvxf XML-LibXML-1.69.tar.gz
rm -f XML-LibXML-1.69.tar.gz
mkdir XML-LibXML-1.69/scripts
cp perl-XML-LibXML_post.sh XML-LibXML-1.69/scripts
chmod +w XML-LibXML-1.69/MANIFEST 
echo "scripts/perl-XML-LibXML_post.sh" >> XML-LibXML-1.69/MANIFEST 
tar -zvcf XML-LibXML-1.69.tar.gz XML-LibXML-1.69
rm -frd XML-LibXML-1.69
mv XML-LibXML-1.69.tar.gz ~/rpmbuild/SOURCES
rpmbuild -ba --sign perl-XML-LibXML.spec
