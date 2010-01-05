#!/bin/sh

defaultstyle=lib/perl5
eval "`perl -V:installstyle`";
eval "`perl -V:installprefix`";
eval "`perl -V:version`";
eval "`perl -V:archname`";

mkdir -p $installprefix/$installstyle/vendor_perl/$version/$archname/Math

if [ -d $installprefix/$installstyle/$archname/Math ];
then
    ln -s $installprefix/$installstyle/$archname/Math/Int64.pm $installprefix/$installstyle/vendor_perl/$version/$archname/Math
    if [ "$installstyle" != "$defaultstyle" ]
    then
        ln -s $installprefix/$installstyle/$archname/Math/Int64.pm $installprefix/$defaultstyle/vendor_perl/$version/$archname/Math
    fi
else
    if [ -d $installprefix/$defaultstyle/$archname/Math ];
    then
        ln -s $installprefix/$defaultstyle/$archname/Math/Int64.pm $installprefix/$installstyle/vendor_perl/$version/$archname/Math
        if [ "$installstyle" != "$defaultstyle" ]
        then
            ln -s $installprefix/$defaultstyle/$archname/Math/Int64.pm $installprefix/$defaultstyle/vendor_perl/$version/$archname/Math
        fi
    fi
fi

mkdir -p $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Math/Int64

if [ -d $installprefix/$installstyle/$archname/auto/Math/Int64 ];
then
    ln -s $installprefix/$installstyle/$archname/auto/Math/Int64/Int64.so $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Math/Int64
    if [ "$installstyle" != "$defaultstyle" ]
    then
        ln -s $installprefix/$installstyle/$archname/auto/Math/Int64/Int64.so $installprefix/$defaultstyle/vendor_perl/$version/$archname/auto/Math/Int64
    fi
else
    if [ -d $installprefix/$defaultstyle/$archname/auto/Math/Int64 ];
    then
        ln -s $installprefix/$defaultstyle/$archname/auto/Math/Int64/Int64.so $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Math/Int64
        if [ "$installstyle" != "$defaultstyle" ]
        then
            ln -s $installprefix/$defaultstyle/$archname/auto/Math/Int64/Int64.so $installprefix/$defaultstyle/vendor_perl/$version/$archname/auto/Math/Int64
        fi
    fi
fi
