#!/bin/sh

eval "`perl -V:installstyle`";
eval "`perl -V:installprefix`";
eval "`perl -V:version`";

mkdir -p $installprefix/$installstyle/vendor_perl/$version/Net/IPTrie
ln -s $installprefix/$installstyle/Net/IPTrie.pm $installprefix/$installstyle/vendor_perl/$version/Net
ln -s $installprefix/$installstyle/Net/IPTrie/Node.pm $installprefix/$installstyle/vendor_perl/$version/Net/IPTrie
