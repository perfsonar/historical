#!/bin/sh

defaultstyle=lib/perl5
eval "`perl -V:installstyle`";
eval "`perl -V:installprefix`";
eval "`perl -V:version`";

mkdir -p $installprefix/$installstyle/vendor_perl/$version/AnyEvent
mkdir -p $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent

if [ -d $installprefix/$installstyle ];
then
    ln -s $installprefix/$installstyle/AnyEvent.pm $installprefix/$installstyle/vendor_perl/$version
    if [ "$installstyle" != "$defaultstyle" ]
    then
        ln -s $installprefix/$installstyle/AnyEvent.pm $installprefix/$defaultstyle/vendor_perl/$version
    fi
else
    if [ -d $installprefix/$defaultstyle/AnyEvent ];
    then
        ln -s $installprefix/$defaultstyle/AnyEvent.pm $installprefix/$installstyle/vendor_perl/$version
        if [ "$installstyle" != "$defaultstyle" ]
        then
            ln -s $installprefix/$defaultstyle/AnyEvent.pm $installprefix/$defaultstyle/vendor_perl/$version
        fi
    fi
fi

if [ -d $installprefix/$installstyle/AnyEvent ];
then
    ln -s $installprefix/$installstyle/AnyEvent/Util.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent
    ln -s $installprefix/$installstyle/AnyEvent/Strict.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent 
    ln -s $installprefix/$installstyle/AnyEvent/DNS.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent
    ln -s $installprefix/$installstyle/AnyEvent/Intro.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent           
    ln -s $installprefix/$installstyle/AnyEvent/TLS.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent 
    ln -s $installprefix/$installstyle/AnyEvent/Socket.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent
    ln -s $installprefix/$installstyle/AnyEvent/Handle.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent     
    if [ "$installstyle" != "$defaultstyle" ]
    then
        ln -s $installprefix/$installstyle/AnyEvent/Util.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent
        ln -s $installprefix/$installstyle/AnyEvent/Strict.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent
        ln -s $installprefix/$installstyle/AnyEvent/DNS.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent
        ln -s $installprefix/$installstyle/AnyEvent/Intro.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent
        ln -s $installprefix/$installstyle/AnyEvent/TLS.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent
        ln -s $installprefix/$installstyle/AnyEvent/Socket.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent
        ln -s $installprefix/$installstyle/AnyEvent/Handle.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent
    fi
else
    if [ -d $installprefix/$defaultstyle/AnyEvent ];
    then
        ln -s $installprefix/$defaultstyle/AnyEvent/Util.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent
        ln -s $installprefix/$defaultstyle/AnyEvent/Strict.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent
        ln -s $installprefix/$defaultstyle/AnyEvent/DNS.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent
        ln -s $installprefix/$defaultstyle/AnyEvent/Intro.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent
        ln -s $installprefix/$defaultstyle/AnyEvent/TLS.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent
        ln -s $installprefix/$defaultstyle/AnyEvent/Socket.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent
        ln -s $installprefix/$defaultstyle/AnyEvent/Handle.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent
        if [ "$installstyle" != "$defaultstyle" ]
        then
            ln -s $installprefix/$defaultstyle/AnyEvent/Util.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent
            ln -s $installprefix/$defaultstyle/AnyEvent/Strict.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent
            ln -s $installprefix/$defaultstyle/AnyEvent/DNS.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent
            ln -s $installprefix/$defaultstyle/AnyEvent/Intro.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent
            ln -s $installprefix/$defaultstyle/AnyEvent/TLS.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent
            ln -s $installprefix/$defaultstyle/AnyEvent/Socket.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent
            ln -s $installprefix/$defaultstyle/AnyEvent/Handle.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent
        fi
    fi
fi

mkdir -p $installprefix/$installstyle/vendor_perl/$version/AnyEvent/Impl
mkdir -p $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent/Impl

if [ -d $installprefix/$installstyle/AnyEvent/Impl ];
then
    ln -s $installprefix/$installstyle/AnyEvent/Impl/IOAsync.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent/Impl
    ln -s $installprefix/$installstyle/AnyEvent/Impl/Perl.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent/Impl
    ln -s $installprefix/$installstyle/AnyEvent/Impl/POE.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent/Impl
    ln -s $installprefix/$installstyle/AnyEvent/Impl/EventLib.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent/Impl
    ln -s $installprefix/$installstyle/AnyEvent/Impl/Qt.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent/Impl
    ln -s $installprefix/$installstyle/AnyEvent/Impl/EV.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent/Impl
    ln -s $installprefix/$installstyle/AnyEvent/Impl/Glib.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent/Impl
    ln -s $installprefix/$installstyle/AnyEvent/Impl/Event.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent/Impl
    ln -s $installprefix/$installstyle/AnyEvent/Impl/Tk.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent/Impl
    if [ "$installstyle" != "$defaultstyle" ]
    then
        ln -s $installprefix/$installstyle/AnyEvent/Impl/IOAsync.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent/Impl
        ln -s $installprefix/$installstyle/AnyEvent/Impl/Perl.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent/Impl
        ln -s $installprefix/$installstyle/AnyEvent/Impl/POE.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent/Impl
        ln -s $installprefix/$installstyle/AnyEvent/Impl/EventLib.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent/Impl
        ln -s $installprefix/$installstyle/AnyEvent/Impl/Qt.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent/Impl
        ln -s $installprefix/$installstyle/AnyEvent/Impl/EV.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent/Impl
        ln -s $installprefix/$installstyle/AnyEvent/Impl/Glib.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent/Impl
        ln -s $installprefix/$installstyle/AnyEvent/Impl/Event.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent/Impl
        ln -s $installprefix/$installstyle/AnyEvent/Impl/Tk.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent/Impl
    fi
else
    if [ -d $installprefix/$defaultstyle/AnyEvent/Impl ];
    then
        ln -s $installprefix/$defaultstyle/AnyEvent/Impl/IOAsync.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent/Impl
        ln -s $installprefix/$defaultstyle/AnyEvent/Impl/Perl.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent/Impl
        ln -s $installprefix/$defaultstyle/AnyEvent/Impl/POE.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent/Impl
        ln -s $installprefix/$defaultstyle/AnyEvent/Impl/EventLib.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent/Impl
        ln -s $installprefix/$defaultstyle/AnyEvent/Impl/Qt.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent/Impl
        ln -s $installprefix/$defaultstyle/AnyEvent/Impl/EV.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent/Impl
        ln -s $installprefix/$defaultstyle/AnyEvent/Impl/Glib.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent/Impl
        ln -s $installprefix/$defaultstyle/AnyEvent/Impl/Event.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent/Impl
        ln -s $installprefix/$defaultstyle/AnyEvent/Impl/Tk.pm $installprefix/$installstyle/vendor_perl/$version/AnyEvent/Impl
        if [ "$installstyle" != "$defaultstyle" ]
        then
            ln -s $installprefix/$defaultstyle/AnyEvent/Impl/IOAsync.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent/Impl
            ln -s $installprefix/$defaultstyle/AnyEvent/Impl/Perl.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent/Impl
            ln -s $installprefix/$defaultstyle/AnyEvent/Impl/POE.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent/Impl
            ln -s $installprefix/$defaultstyle/AnyEvent/Impl/EventLib.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent/Impl
            ln -s $installprefix/$defaultstyle/AnyEvent/Impl/Qt.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent/Impl
            ln -s $installprefix/$defaultstyle/AnyEvent/Impl/EV.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent/Impl
            ln -s $installprefix/$defaultstyle/AnyEvent/Impl/Glib.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent/Impl
            ln -s $installprefix/$defaultstyle/AnyEvent/Impl/Event.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent/Impl
            ln -s $installprefix/$defaultstyle/AnyEvent/Impl/Tk.pm $installprefix/$defaultstyle/vendor_perl/$version/AnyEvent/Impl
        fi
    fi
fi
