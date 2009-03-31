#!/bin/sh

eval "`perl -V:installstyle`";
eval "`perl -V:installprefix`";
eval "`perl -V:version`";
eval "`perl -V:archname`";

mkdir -p $installprefix/$installstyle/vendor_perl/$version/Data/Validate
ln -s $installprefix/$installstyle/Data/Validate/IP.pm $installprefix/$installstyle/vendor_perl/$version/Data/Validate

mkdir -p $installprefix/$installstyle/vendor_perl/$version/$archname/auto/Data/Validate/IP
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



