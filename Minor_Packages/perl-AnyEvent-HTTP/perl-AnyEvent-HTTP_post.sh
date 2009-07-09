#!/bin/sh

defaultstyle=lib/perl5
eval "`perl -V:installstyle`";
eval "`perl -V:installprefix`";
eval "`perl -V:version`";

mkdir -p $installprefix/$installstyle/vendor_perl/$version/AnyEvent
mkdir -p $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent

if [ -d $installprefix/$installstyle/AnyEvent ];
then
    ln -s $installprefix/$installstyle/AnyEvent/HTTP.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent
    if [ "$installstyle" != "$defaultstyle" ]
    then
        ln -s $installprefix/$installstyle/AnyEvent/HTTP.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent
    fi
else
    if [ -d $installprefix/$defaultstyle/AnyEvent ];
    then
        ln -s $installprefix/$defaultstyle/AnyEvent/HTTP.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent
        if [ "$installstyle" != "$defaultstyle" ]
        then
            ln -s $installprefix/$defaultstyle/AnyEvent/HTTP.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent
        fi
    fi
fi
