#!/bin/sh

rm -frd ~/rpmbuild/BUILD/Net-IPTrie*
rm -frd ~/rpmbuild/SOURCES/Net-IPTrie*
rm -frd ~/rpmbuild/tmp/*
rm -frd ~/rpmbuild/RPMS/noarch/perl-Net-IPTrie*
rm -frd ~/rpmbuild/SRPMS/perl-Net-IPTrie*

wget -c http://search.cpan.org/CPAN/authors/id/C/CV/CVICENTE/Net-IPTrie-v0.4.tar.gz
tar -zvxf Net-IPTrie-v0.4.tar.gz
rm -f Net-IPTrie-v0.4.tar.gz
mkdir Net-IPTrie-v0.4/scripts
cp perl-Net-IPTrie_post.sh Net-IPTrie-v0.4/scripts
chmod +w Net-IPTrie-v0.4/MANIFEST 
echo "scripts/perl-Net-IPTrie_post.sh" >> Net-IPTrie-v0.4/MANIFEST 
tar -zvcf Net-IPTrie-v0.4.tar.gz Net-IPTrie-v0.4
rm -frd Net-IPTrie-v0.4
mv Net-IPTrie-v0.4.tar.gz ~/rpmbuild/SOURCES
rpmbuild -ba --sign perl-Net-IPTrie.spec
