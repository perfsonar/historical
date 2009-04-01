#!/bin/sh

eval "`perl -V:installstyle`";
eval "`perl -V:installprefix`";
eval "`perl -V:version`";
eval "`perl -V:archname`";

mkdir -p $installprefix/$installstyle/vendor_perl/$version/$archname/auto/XML/LibXML
mkdir -p $installprefix/$installstyle/vendor_perl/$version/$archname/XML/LibXML/SAX

for i in `ls $installprefix/$installstyle/$archname/auto/XML/LibXML`
do
    ln -s $installprefix/$installstyle/$archname/auto/XML/LibXML/$i $installprefix/$installstyle/vendor_perl/$version/$archname/auto/XML/LibXML
done

for i in `ls $installprefix/$installstyle/$archname/XML`
do
    ln -s $installprefix/$installstyle/$archname/XML/$i $installprefix/$installstyle/vendor_perl/$version/$archname/XML
done

for i in `ls $installprefix/$installstyle/$archname/XML/LibXML`
do
    ln -s $installprefix/$installstyle/$archname/XML/LibXML/$i $installprefix/$installstyle/vendor_perl/$version/$archname/XML/LibXML
done

for i in `ls $installprefix/$installstyle/$archname/XML/LibXML/SAX`
do
    ln -s $installprefix/$installstyle/$archname/XML/LibXML/SAX/$i $installprefix/$installstyle/vendor_perl/$version/$archname/XML/LibXML/SAX
done
