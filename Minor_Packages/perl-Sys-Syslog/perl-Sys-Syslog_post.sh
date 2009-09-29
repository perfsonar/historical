#!/bin/sh

defaultstyle=lib/perl5
eval "`perl -V:installstyle`";
eval "`perl -V:installprefix`";
eval "`perl -V:version`";
eval "`perl -V:archname`";

mkdir -p $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Sys/Syslog
mkdir -p $installprefix/$defaultstyle/vendor_perl/$version/$archname/auto/Sys/Syslog
mkdir -p $installprefix/$installstyle/vendor_perl/$version/$archname/Sys
mkdir -p $installprefix/$defaultstyle/vendor_perl/$version/$archname/Sys

if [ -d $installprefix/$installstyle/$archname/auto/Sys/Syslog ];
then
    ln -s $installprefix/$installstyle/$archname/auto/Sys/Syslog/Syslog.so $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Sys/Syslog
    if [ "$installstyle" != "$defaultstyle" ]
    then
        ln -s $installprefix/$installstyle/$archname/auto/Sys/Syslog/Syslog.so $installprefix/$defaultstyle/vendor_perl/$version/$archname/auto/Sys/Syslog
    fi
else
    if [ -d $installprefix/$defaultstyle/$archname/auto/Sys/Syslog ];
    then
        ln -s $installprefix/$defaultstyle/$archname/auto/Sys/Syslog/Syslog.so $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Sys/Syslog     
        if [ "$installstyle" != "$defaultstyle" ]
        then
            ln -s $installprefix/$defaultstyle/$archname/auto/Sys/Syslog/Syslog.so $installprefix/$defaultstyle/vendor_perl/$version/$archname/auto/Sys/Syslog
        fi
    fi
fi

if [ -d $installprefix/$installstyle/$archname/Sys ];
then
    ln -s $installprefix/$installstyle/$archname/Sys/Syslog.pm $installprefix/$installstyle/vendor_perl/$version/$archname/Sys
    if [ "$installstyle" != "$defaultstyle" ]
    then
        ln -s $installprefix/$installstyle/$archname/Sys/Syslog.pm $installprefix/$defaultstyle/vendor_perl/$version/$archname/Sys
    fi
else
    if [ -d $installprefix/$defaultstyle/$archname/Sys ];
    then
        ln -s $installprefix/$defaultstyle/$archname/Sys/Syslog.pm $installprefix/$installstyle/vendor_perl/$version/$archname/Sys
        if [ "$installstyle" != "$defaultstyle" ]
        then
            ln -s $installprefix/$defaultstyle/$archname/Sys/Syslog.pm $installprefix/$defaultstyle/vendor_perl/$version/$archname/Sys
        fi
    fi
fi
