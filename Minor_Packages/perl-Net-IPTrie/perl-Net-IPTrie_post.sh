#!/bin/sh

defaultstyle=lib/perl5
eval "`perl -V:installstyle`";
eval "`perl -V:installprefix`";
eval "`perl -V:version`";

mkdir -p $installprefix/$installstyle/vendor_perl/$version/Net/IPTrie
mkdir -p $installprefix/$defaultstyle/vendor_perl/$version/Net/IPTrie

if [ -d $installprefix/$installstyle/Net ];
then
    ln -s $installprefix/$installstyle/Net/IPTrie.pm $installprefix/$installstyle/vendor_perl/$version/Net
    if [ "$installstyle" != "$defaultstyle" ]
    then
        ln -s $installprefix/$installstyle/Net/IPTrie.pm $installprefix/$defaultstyle/vendor_perl/$version/Net
    fi
else
    if [ -d $installprefix/$defaultstyle/Net ];
    then
        ln -s $installprefix/$defaultstyle/Net/IPTrie.pm $installprefix/$installstyle/vendor_perl/$version/Net
        if [ "$installstyle" != "$defaultstyle" ]
        then
            ln -s $installprefix/$defaultstyle/Net/IPTrie.pm $installprefix/$defaultstyle/vendor_perl/$version/Net
        fi
    fi
fi

if [ -d $installprefix/$installstyle/Net/IPTrie ];
then
    ln -s $installprefix/$installstyle/Net/IPTrie/Node.pm $installprefix/$installstyle/vendor_perl/$version/Net/IPTrie
    if [ "$installstyle" != "$defaultstyle" ]
    then
        ln -s $installprefix/$installstyle/Net/IPTrie/Node.pm $installprefix/$defaultstyle/vendor_perl/$version/Net/IPTrie
    fi
else
    if [ -d $installprefix/$defaultstyle/Net/IPTrie ];
    then
        ln -s $installprefix/$defaultstyle/Net/IPTrie/Node.pm $installprefix/$installstyle/vendor_perl/$version/Net/IPTrie
        if [ "$installstyle" != "$defaultstyle" ]
        then
            ln -s $installprefix/$defaultstyle/Net/IPTrie/Node.pm $installprefix/$defaultstyle/vendor_perl/$version/Net/IPTrie
        fi
    fi
fi

