#!/bin/sh

defaultstyle=lib/perl5
eval "`perl -V:installstyle`";
eval "`perl -V:installprefix`";
eval "`perl -V:version`";
eval "`perl -V:archname`";

mkdir -p $installprefix/$installstyle/vendor_perl/$version/Data/Validate
mkdir -p $installprefix/$defaultstyle/vendor_perl/$version/Data/Validate

if [ -d $installprefix/$installstyle/Data/Validate ];
then
    ln -s $installprefix/$installstyle/Data/Validate/Domain.pm $installprefix/$installstyle/vendor_perl/$version/Data/Validate
    if [ "$installstyle" != "$defaultstyle" ]
    then
        ln -s $installprefix/$installstyle/Data/Validate/Domain.pm $installprefix/$defaultstyle/vendor_perl/$version/Data/Validate
    fi
else
    if [ -d $installprefix/$defaultstyle/Data/Validate ];
    then
        ln -s $installprefix/$defaultstyle/Data/Validate/Domain.pm $installprefix/$installstyle/vendor_perl/$version/Data/Validate
        if [ "$installstyle" != "$defaultstyle" ]
        then
            ln -s $installprefix/$defaultstyle/Data/Validate/Domain.pm $installprefix/$defaultstyle/vendor_perl/$version/Data/Validate
        fi
    fi
fi






