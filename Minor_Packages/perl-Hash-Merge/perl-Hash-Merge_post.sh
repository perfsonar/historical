#!/bin/sh

defaultstyle=lib/perl5
eval "`perl -V:installstyle`";
eval "`perl -V:installprefix`";
eval "`perl -V:version`";
eval "`perl -V:archname`";

mkdir -p $installprefix/$installstyle/vendor_perl/$version/Hash
mkdir -p $installprefix/$defaultstyle/vendor_perl/$version/Hash

if [ -d $installprefix/$installstyle/Hash ];
then
    ln -s $installprefix/$installstyle/Hash/Merge.pm $installprefix/$installstyle/vendor_perl/$version/Hash
    if [ "$installstyle" != "$defaultstyle" ]
    then
        ln -s $installprefix/$installstyle/Hash/Merge.pm $installprefix/$defaultstyle/vendor_perl/$version/Hash
    fi
else
    if [ -d $installprefix/$defaultstyle/Hash ];
    then
        ln -s $installprefix/$defaultstyle/Hash/Merge.pm $installprefix/$installstyle/vendor_perl/$version/Hash
        if [ "$installstyle" != "$defaultstyle" ]
        then
            ln -s $installprefix/$defaultstyle/Hash/Merge.pm $installprefix/$defaultstyle/vendor_perl/$version/Hash
        fi
    fi
fi

