#!/bin/sh

defaultstyle=lib/perl5
eval "`perl -V:installstyle`";
eval "`perl -V:installprefix`";
eval "`perl -V:version`";
eval "`perl -V:archname`";

mkdir -p $installprefix/$installstyle/vendor_perl/$version/$archname/auto/XML/LibXML

if [ -d $installprefix/$installstyle/$archname/auto/XML/LibXML ];
then
    for i in `ls $installprefix/$installstyle/$archname/auto/XML/LibXML`
    do
        ln -s $installprefix/$installstyle/$archname/auto/XML/LibXML/$i $installprefix/$installstyle/vendor_perl/$version/$archname/auto/XML/LibXML
    done
else
    if [ -d $installprefix/$defaultstyle/$archname/auto/XML/LibXML ];
    then
        for i in `ls $installprefix/$defaultstyle/$archname/auto/XML/LibXML`
        do
            ln -s $installprefix/$defaultstyle/$archname/auto/XML/LibXML/$i $installprefix/$installstyle/vendor_perl/$version/$archname/auto/XML/LibXML
        done    
    fi
fi

if [ -d $installprefix/$installstyle/$archname/XML ];
then
    for i in `ls $installprefix/$installstyle/$archname/XML`
    do
        ln -s $installprefix/$installstyle/$archname/XML/$i $installprefix/$installstyle/vendor_perl/$version/$archname/XML
    done
else
    if [ -d $installprefix/$defaultstyle/$archname/XML ];
    then
        for i in `ls $installprefix/$defaultstyle/$archname/XML`
        do
            ln -s $installprefix/$defaultstyle/$archname/XML/$i $installprefix/$installstyle/vendor_perl/$version/$archname/XML
        done
    fi
fi

if [ -d $installprefix/$installstyle/$archname/XML/LibXML ];
then
    for i in `ls $installprefix/$installstyle/$archname/XML/LibXML`
    do
        ln -s $installprefix/$installstyle/$archname/XML/LibXML/$i $installprefix/$installstyle/vendor_perl/$version/$archname/XML/LibXML
    done
else
    if [ -d $installprefix/$defaultstyle/$archname/XML/LibXML ];
    then

        for i in `ls $installprefix/$defaultstyle/$archname/XML/LibXML`
        do
            ln -s $installprefix/$defaultstyle/$archname/XML/LibXML/$i $installprefix/$installstyle/vendor_perl/$version/$archname/XML/LibXML
        done
    fi
fi

mkdir -p $installprefix/$installstyle/vendor_perl/$version/$archname/XML/LibXML/SAX

if [ -d $installprefix/$installstyle/$archname/XML/LibXML/SAX ];
then
    for i in `ls $installprefix/$installstyle/$archname/XML/LibXML/SAX`
    do
        ln -s $installprefix/$installstyle/$archname/XML/LibXML/SAX/$i $installprefix/$installstyle/vendor_perl/$version/$archname/XML/LibXML/SAX
    done

else
    if [ -d $installprefix/$defaultstyle/$archname/XML/LibXML/SAX ];
    then

        for i in `ls $installprefix/$defaultstyle/$archname/XML/LibXML/SAX`
        do
            ln -s $installprefix/$defaultstyle/$archname/XML/LibXML/SAX/$i $installprefix/$installstyle/vendor_perl/$version/$archname/XML/LibXML/SAX
        done
    fi
fi
