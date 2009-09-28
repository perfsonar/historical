#!/bin/sh

defaultstyle=lib/perl5
eval "`perl -V:installstyle`";
eval "`perl -V:installprefix`";
eval "`perl -V:version`";
eval "`perl -V:archname`";

mkdir -p $installprefix/$installstyle/vendor_perl/$version/$archname/NetAddr/IP
mkdir -p $installprefix/$defaultstyle/vendor_perl/$version/$archname/NetAddr/IP

if [ -d $installprefix/$installstyle/$archname/NetAddr ];
then
    ln -s $installprefix/$installstyle/$archname/NetAddr/IP.pm $installprefix/$installstyle/vendor_perl/$version/$archname/NetAddr
    if [ "$installstyle" != "$defaultstyle" ]
    then
        ln -s $installprefix/$installstyle/$archname/NetAddr/IP.pm $installprefix/$defaultstyle/vendor_perl/$version/$archname/NetAddr
    fi
else
    if [ -d $installprefix/$defaultstyle/$archname/NetAddr ];
    then
        ln -s $installprefix/$defaultstyle/$archname/NetAddr/IP.pm $installprefix/$installstyle/vendor_perl/$version/$archname/NetAddr      
        if [ "$installstyle" != "$defaultstyle" ]
        then
            ln -s $installprefix/$defaultstyle/$archname/NetAddr/IP.pm $installprefix/$defaultstyle/vendor_perl/$version/$archname/NetAddr
        fi
    fi
fi

if [ -d $installprefix/$installstyle/$archname/NetAddr/IP ];
then
    ln -s $installprefix/$installstyle/$archname/NetAddr/IP/UtilPP.pm $installprefix/$installstyle/vendor_perl/$version/$archname/NetAddr/IP
    ln -s $installprefix/$installstyle/$archname/NetAddr/IP/Util.pm $installprefix/$installstyle/vendor_perl/$version/$archname/NetAddr/IP
    ln -s $installprefix/$installstyle/$archname/NetAddr/IP/Lite.pm $installprefix/$installstyle/vendor_perl/$version/$archname/NetAddr/IP
    ln -s $installprefix/$installstyle/$archname/NetAddr/IP/Util_IS.pm $installprefix/$installstyle/vendor_perl/$version/$archname/NetAddr/IP
    if [ "$installstyle" != "$defaultstyle" ]
    then
        ln -s $installprefix/$installstyle/$archname/NetAddr/IP/UtilPP.pm $installprefix/$defaultstyle/vendor_perl/$version/$archname/NetAddr/IP
        ln -s $installprefix/$installstyle/$archname/NetAddr/IP/Util.pm $installprefix/$defaultstyle/vendor_perl/$version/$archname/NetAddr/IP
        ln -s $installprefix/$installstyle/$archname/NetAddr/IP/Lite.pm $installprefix/$defaultstyle/vendor_perl/$version/$archname/NetAddr/IP
        ln -s $installprefix/$installstyle/$archname/NetAddr/IP/Util_IS.pm $installprefix/$defaultstyle/vendor_perl/$version/$archname/NetAddr/IP
    fi
else
    if [ -d $installprefix/$defaultstyle/$archname/NetAddr/IP ];
    then
        ln -s $installprefix/$defaultstyle/$archname/NetAddr/IP/UtilPP.pm $installprefix/$installstyle/vendor_perl/$version/$archname/NetAddr/IP
        ln -s $installprefix/$defaultstyle/$archname/NetAddr/IP/Util.pm $installprefix/$installstyle/vendor_perl/$version/$archname/NetAddr/IP
        ln -s $installprefix/$defaultstyle/$archname/NetAddr/IP/Lite.pm $installprefix/$installstyle/vendor_perl/$version/$archname/NetAddr/IP
        ln -s $installprefix/$defaultstyle/$archname/NetAddr/IP/Util_IS.pm $installprefix/$installstyle/vendor_perl/$version/$archname/NetAddr/IP        
        if [ "$installstyle" != "$defaultstyle" ]
        then
            ln -s $installprefix/$defaultstyle/$archname/NetAddr/IP/UtilPP.pm $installprefix/$defaultstyle/vendor_perl/$version/$archname/NetAddr/IP
            ln -s $installprefix/$defaultstyle/$archname/NetAddr/IP/Util.pm $installprefix/$defaultstyle/vendor_perl/$version/$archname/NetAddr/IP
            ln -s $installprefix/$defaultstyle/$archname/NetAddr/IP/Lite.pm $installprefix/$defaultstyle/vendor_perl/$version/$archname/NetAddr/IP
            ln -s $installprefix/$defaultstyle/$archname/NetAddr/IP/Util_IS.pm $installprefix/$defaultstyle/vendor_perl/$version/$archname/NetAddr/IP 
        fi
    fi
fi

mkdir -p $installprefix/$installstyle/vendor_perl/$version/$archname/auto/NetAddr/IP/Util
mkdir -p $installprefix/$defaultstyle/vendor_perl/$version/$archname/auto/NetAddr/IP/Util
mkdir -p $installprefix/$installstyle/vendor_perl/$version/$archname/auto/NetAddr/IP/UtilPP
mkdir -p $installprefix/$defaultstyle/vendor_perl/$version/$archname/auto/NetAddr/IP/UtilPP

if [ -d $installprefix/$installstyle/$archname/auto/NetAddr/IP ];
then
    for i in `ls $installprefix/$installstyle/$archname/auto/NetAddr/IP`
    do
        ln -s $installprefix/$installstyle/$archname/auto/NetAddr/IP/$i $installprefix/$installstyle/vendor_perl/$version/$archname/auto/NetAddr/IP
    done
    if [ "$installstyle" != "$defaultstyle" ]
    then
        for i in `ls $installprefix/$installstyle/$archname/auto/NetAddr/IP`
        do
            ln -s $installprefix/$installstyle/$archname/auto/NetAddr/IP/$i $installprefix/$defaultstyle/vendor_perl/$version/$archname/auto/NetAddr/IP
        done
    fi
else
    if [ -d $installprefix/$defaultstyle/$archname/auto/NetAddr/IP ];
    then
        for i in `ls $installprefix/$defaultstyle/$archname/auto/NetAddr/IP`
        do
            ln -s $installprefix/$defaultstyle/$archname/auto/NetAddr/IP/$i $installprefix/$installstyle/vendor_perl/$version/$archname/auto/NetAddr/IP
        done
        if [ "$installstyle" != "$defaultstyle" ]
        then
            for i in `ls $installprefix/$defaultstyle/$archname/auto/NetAddr/IP`
            do
                ln -s $installprefix/$defaultstyle/$archname/auto/NetAddr/IP/$i $installprefix/$defaultstyle/vendor_perl/$version/$archname/auto/NetAddr/IP
            done
        fi
    fi
fi

if [ -d $installprefix/$installstyle/$archname/auto/NetAddr/IP/Util ];
then
    for i in `ls $installprefix/$installstyle/$archname/auto/NetAddr/IP/Util`
    do
        ln -s $installprefix/$installstyle/$archname/auto/NetAddr/IP/Util/$i $installprefix/$installstyle/vendor_perl/$version/$archname/auto/NetAddr/IP/Util
    done
    if [ "$installstyle" != "$defaultstyle" ]
    then
        for i in `ls $installprefix/$installstyle/$archname/auto/NetAddr/IP/Util`
        do
            ln -s $installprefix/$installstyle/$archname/auto/NetAddr/IP/Util/$i $installprefix/$defaultstyle/vendor_perl/$version/$archname/auto/NetAddr/IP/Util
        done
    fi
else
    if [ -d $installprefix/$defaultstyle/$archname/auto/NetAddr/IP/Util ];
    then
        for i in `ls $installprefix/$defaultstyle/$archname/auto/NetAddr/IP/Util`
        do
            ln -s $installprefix/$defaultstyle/$archname/auto/NetAddr/IP/Util/$i $installprefix/$installstyle/vendor_perl/$version/$archname/auto/NetAddr/IP/Util
        done
        if [ "$installstyle" != "$defaultstyle" ]
        then
            for i in `ls $installprefix/$defaultstyle/$archname/auto/NetAddr/IP/Util`
            do
                ln -s $installprefix/$defaultstyle/$archname/auto/NetAddr/IP/Util/$i $installprefix/$defaultstyle/vendor_perl/$version/$archname/auto/NetAddr/IP/Util
            done
        fi
    fi
fi

if [ -d $installprefix/$installstyle/$archname/auto/NetAddr/IP/UtilPP ];
then

    for i in `ls $installprefix/$installstyle/$archname/auto/NetAddr/IP/UtilPP`
    do
        ln -s $installprefix/$installstyle/$archname/auto/NetAddr/IP/UtilPP/$i $installprefix/$installstyle/vendor_perl/$version/$archname/auto/NetAddr/IP/UtilPP
    done
    if [ "$installstyle" != "$defaultstyle" ]
    then
        for i in `ls $installprefix/$installstyle/$archname/auto/NetAddr/IP/UtilPP`
        do
            ln -s $installprefix/$installstyle/$archname/auto/NetAddr/IP/UtilPP/$i $installprefix/$defaultstyle/vendor_perl/$version/$archname/auto/NetAddr/IP/UtilPP
        done
    fi
else
    if [ -d $installprefix/$defaultstyle/$archname/auto/NetAddr/IP/UtilPP ];
    then
        for i in `ls $installprefix/$defaultstyle/$archname/auto/NetAddr/IP/UtilPP`
        do
            ln -s $installprefix/$defaultstyle/$archname/auto/NetAddr/IP/UtilPP/$i $installprefix/$installstyle/vendor_perl/$version/$archname/auto/NetAddr/IP/UtilPP
        done
        if [ "$installstyle" != "$defaultstyle" ]
        then
            for i in `ls $installprefix/$defaultstyle/$archname/auto/NetAddr/IP/UtilPP`
            do
                ln -s $installprefix/$defaultstyle/$archname/auto/NetAddr/IP/UtilPP/$i $installprefix/$defaultstyle/vendor_perl/$version/$archname/auto/NetAddr/IP/UtilPP
            done
        fi
    fi
fi
