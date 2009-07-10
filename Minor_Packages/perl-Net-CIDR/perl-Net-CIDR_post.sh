#!/bin/sh

defaultstyle=lib/perl5
eval "`perl -V:installstyle`";
eval "`perl -V:installprefix`";
eval "`perl -V:version`";

mkdir -p $installprefix/$installstyle/vendor_perl/$version/Net
mkdir -p $installprefix/$defaultstyle/vendor_perl/$version/Net

if [ -f $installprefix/$installstyle/Net/CIDR.pm ];
then
    ln -s $installprefix/$installstyle/Net/CIDR.pm $installprefix/$installstyle/vendor_perl/$version/Net
    if [ "$installstyle" != "$defaultstyle" ]
    then
        ln -s $installprefix/$installstyle/Net/CIDR.pm $installprefix/$defaultstyle/vendor_perl/$version/Net
    fi
else
    if [ -f $installprefix/$defaultstyle/Net/CIDR.pm ];
    then
        ln -s $installprefix/$defaultstyle/Net/CIDR.pm $installprefix/$installstyle/vendor_perl/$version/Net
        if [ "$installstyle" != "$defaultstyle" ]
        then
            ln -s $installprefix/$defaultstyle/Net.pm $installprefix/$defaultstyle/vendor_perl/$version/Net
        fi
    fi
fi
