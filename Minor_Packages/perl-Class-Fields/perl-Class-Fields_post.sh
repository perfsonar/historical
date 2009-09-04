#!/bin/sh

defaultstyle=lib/perl5
eval "`perl -V:installstyle`";
eval "`perl -V:installprefix`";
eval "`perl -V:version`";

mkdir -p $installprefix/$installstyle/vendor_perl/$version/Class/Fields
mkdir -p $installprefix/$defaultstyle/vendor_perl/$version/Class/Fields

if [ -f $installprefix/$installstyle/Class/Fields.pm ];
then
    ln -s $installprefix/$installstyle/Class/Fields.pm $installprefix/$installstyle/vendor_perl/$version/Class
    if [ "$installstyle" != "$defaultstyle" ]
    then
        ln -s $installprefix/$installstyle/Class/Fields.pm $installprefix/$defaultstyle/vendor_perl/$version/Class
    fi
else
    if [ -f $installprefix/$defaultstyle/Class/Fields.pm ];
    then
        ln -s $installprefix/$defaultstyle/Class/Fields.pm $installprefix/$installstyle/vendor_perl/$version/Class
        if [ "$installstyle" != "$defaultstyle" ]
        then
            ln -s $installprefix/$defaultstyle/Class/Fields.pm $installprefix/$defaultstyle/vendor_perl/$version/Class
        fi
    fi
fi

if [ -d $installprefix/$installstyle/ClassFields ];
then
    ln -s $installprefix/$installstyle/Class/Fields/Inherit.pm $installprefix/$installstyle/vendor_perl/$version/Class/Fields
    ln -s $installprefix/$installstyle/Class/Fields/Fuxor.pm $installprefix/$installstyle/vendor_perl/$version/Class/Fields   
    ln -s $installprefix/$installstyle/Class/Fields/Attribs.pm $installprefix/$installstyle/vendor_perl/$version/Class/Fields    
    if [ "$installstyle" != "$defaultstyle" ]
    then
        ln -s $installprefix/$installstyle/Class/Fields/Inherit.pm $installprefix/$defaultstyle/vendor_perl/$version/Class/Fields
        ln -s $installprefix/$installstyle/Class/Fields/Fuxor.pm $installprefix/$defaultstyle/vendor_perl/$version/Class/Fields
        ln -s $installprefix/$installstyle/Class/Fields/Attribs.pm $installprefix/$defaultstyle/vendor_perl/$version/Class/Fields
    fi
else
    if [ -d $installprefix/$defaultstyle/Class/Fields ];
    then
        ln -s $installprefix/$defaultstyle/Class/Fields/Inherit.pm $installprefix/$installstyle/vendor_perl/$version/Class/Fields
        ln -s $installprefix/$defaultstyle/Class/Fields/Fuxor.pm $installprefix/$installstyle/vendor_perl/$version/Class/Fields
        ln -s $installprefix/$defaultstyle/Class/Fields/Attribs.pm $installprefix/$installstyle/vendor_perl/$version/Class/Fields
        if [ "$installstyle" != "$defaultstyle" ]
        then
            ln -s $installprefix/$defaultstyle/Class/Fields/Inherit.pm $installprefix/$defaultstyle/vendor_perl/$version/Class/Fields
            ln -s $installprefix/$defaultstyle/Class/Fields/Fuxor.pm $installprefix/$defaultstyle/vendor_perl/$version/Class/Fields
            ln -s $installprefix/$defaultstyle/Class/Fields/Attribs.pm $installprefix/$defaultstyle/vendor_perl/$version/Class/Fields
        fi
    fi
fi
