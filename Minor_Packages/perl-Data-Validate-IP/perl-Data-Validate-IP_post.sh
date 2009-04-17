#!/bin/sh

defaultstyle=lib/perl5
eval "`perl -V:installstyle`";
eval "`perl -V:installprefix`";
eval "`perl -V:version`";
eval "`perl -V:archname`";

mkdir -p $installprefix/$installstyle/vendor_perl/$version/Data/Validate

if [ -d $installprefix/$installstyle/Data/Validate ];
then
    ln -s $installprefix/$installstyle/Data/Validate/IP.pm $installprefix/$installstyle/vendor_perl/$version/Data/Validate
else
    if [ -d $installprefix/$defaultstyle/Data/Validate ];
    then
        ln -s $installprefix/$defaultstyle/Data/Validate/IP.pm $installprefix/$installstyle/vendor_perl/$version/Data/Validate
    fi
fi

mkdir -p $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Data/Validate/IP

if [ -d $installprefix/$installstyle/auto/Data/Validate/IP ];
then
    ln -s $installprefix/$installstyle/auto/Data/Validate/IP/is_loopback_ipv4.al $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Data/Validate/IP
    ln -s $installprefix/$installstyle/auto/Data/Validate/IP/is_linklocal_ipv4.al $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Data/Validate/IP
    ln -s $installprefix/$installstyle/auto/Data/Validate/IP/is_testnet_ipv4.al $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Data/Validate/IP
    ln -s $installprefix/$installstyle/auto/Data/Validate/IP/is_public_ipv4.al $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Data/Validate/IP
    ln -s $installprefix/$installstyle/auto/Data/Validate/IP/_mask.al $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Data/Validate/IP
    ln -s $installprefix/$installstyle/auto/Data/Validate/IP/new.al $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Data/Validate/IP
    ln -s $installprefix/$installstyle/auto/Data/Validate/IP/is_ipv4.al $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Data/Validate/IP
    ln -s $installprefix/$installstyle/auto/Data/Validate/IP/autosplit.ix $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Data/Validate/IP
    ln -s $installprefix/$installstyle/auto/Data/Validate/IP/is_private_ipv4.al $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Data/Validate/IP
    ln -s $installprefix/$installstyle/auto/Data/Validate/IP/is_multicast_ipv4.al $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Data/Validate/IP
else
    if [ -d $installprefix/$defaultstyle/auto/Data/Validate/IP ];
    then
        ln -s $installprefix/$defaultstyle/auto/Data/Validate/IP/is_loopback_ipv4.al $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Data/Validate/IP
        ln -s $installprefix/$defaultstyle/auto/Data/Validate/IP/is_linklocal_ipv4.al $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Data/Validate/IP
        ln -s $installprefix/$defaultstyle/auto/Data/Validate/IP/is_testnet_ipv4.al $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Data/Validate/IP
        ln -s $installprefix/$defaultstyle/auto/Data/Validate/IP/is_public_ipv4.al $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Data/Validate/IP
        ln -s $installprefix/$defaultstyle/auto/Data/Validate/IP/_mask.al $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Data/Validate/IP
        ln -s $installprefix/$defaultstyle/auto/Data/Validate/IP/new.al $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Data/Validate/IP
        ln -s $installprefix/$defaultstyle/auto/Data/Validate/IP/is_ipv4.al $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Data/Validate/IP
        ln -s $installprefix/$defaultstyle/auto/Data/Validate/IP/autosplit.ix $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Data/Validate/IP
        ln -s $installprefix/$defaultstyle/auto/Data/Validate/IP/is_private_ipv4.al $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Data/Validate/IP
        ln -s $installprefix/$defaultstyle/auto/Data/Validate/IP/is_multicast_ipv4.al $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Data/Validate/IP
    fi
fi






