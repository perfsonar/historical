#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

tree.cgi - Contact each know gLS instances and dump the contents.  

=head1 DESCRIPTION

For each gLS instance, dump it's known knowledge of hLS isntance, and then dump
each hLS's knowledge of registered services.

=cut

use HTML::Template;
use CGI;
use CGI::Carp;

use FindBin qw($RealBin);
my $basedir = "$RealBin/";
use lib "$RealBin/../lib";

my $base     = "/var/lib/perfsonar/perfAdmin/cache";
my $template = HTML::Template->new( filename => "$RealBin/../etc/tree.tmpl" );
my $CGI      = CGI->new();

my $lastMod = "at an unknown time...";

my $gLSFile    = $base . "/list.glsmap";
my $hLSMapFile = $base . "/list.hlsmap";
my $hLSFile    = $base . "/list.hls";
my @glslist    = ();
my @hlslist    = ();
my @list       = ();
if ( -f $gLSFile and $hLSMapFile and $hLSFile ) {
    my ( $mtime ) = ( stat( $gLSFile ) )[9];
    $lastMod = "on " . gmtime( $mtime ) . " UTC";

    open( READ, "<" . $gLSFile ) or croak "Can't open gLS Map File";
    my @glscontent = <READ>;
    close( READ );

    open( READ2, "<" . $hLSMapFile ) or croak "Can't open hLS Map File";
    my @hlscontent = <READ2>;
    close( READ2 );

    open( READ3, "<" . $hLSFile ) or croak "Can't open hLS File";
    my @hlscontent2 = <READ3>;
    close( READ3 );

    my $counter = 1;
    foreach my $c ( @glscontent ) {
        $c =~ s/\n//g;
        my @gls = split( /\|/, $c );
        my @hls = split( /,/,  $gls[1] );
        my @hls_list = ();
        foreach my $h ( @hls ) {
            my @service_list = ();
            foreach my $c2 ( @hlscontent ) {
                $c2 =~ s/\n//g;
                my @hls2 = split( /\|/, $c2 );
                next unless $h eq $hls2[0];
                my @services = split( /,/, $hls2[1] );
                foreach my $s ( @services ) {
                    next unless $s =~ m/^http:\/\//;
                    push @service_list, { NAME => $s };
                }
                last;
            }
            push @hls_list, { NAME => $h, SERVICES => \@service_list };
        }
        push @glslist, { NAME => $gls[0], COUNT => $counter };
        push @list,    { NAME => $gls[0], HLS   => \@hls_list };
        $counter++;
    }

    $counter = 1;
    foreach my $c ( @hlscontent2 ) {
        $c =~ s/\n//g;
        my @fields = split( /\|/, $c );
        push @hlslist, { NAME => $fields[0], COUNT => $counter, DESC => $fields[3] };
        $counter++;
    }

}
else {

    # do something...
}

print $CGI->header();

$template->param(
    MOD          => $lastMod,
    GLS          => \@list,
    GLSINSTANCES => \@glslist,
    HLSINSTANCES => \@hlslist
);

print $template->output;

__END__

=head1 SEE ALSO

L<C>

To join the 'perfSONAR-PS Users' mailing list, please visit:

  https://lists.internet2.edu/sympa/info/perfsonar-ps-users

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS/trunk

Questions and comments can be directed to the author, or the mailing list.  Bugs,
feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 COPYRIGHT

Copyright (c) 2007-2010, Internet2

All rights reserved.

=cut
