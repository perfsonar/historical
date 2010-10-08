#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

view.cgi - View the contents of an hLS. 

=head1 DESCRIPTION

Supply an hLs argument, and see the internal XML contents of that hLS.

=cut

use CGI;
use HTML::Template;
use XML::LibXML;
use CGI::Carp qw(fatalsToBrowser);
use English qw( -no_match_vars );

use FindBin qw($RealBin);
my $basedir = "$RealBin/";
use lib "$RealBin/../lib";

use perfSONAR_PS::Client::DCN;
use perfSONAR_PS::Common qw( unescapeString escapeString find extract );

my $cgi    = new CGI;
my $parser = XML::LibXML->new();

croak "hLS instance not provided unless " unless $cgi->param( 'hls' );

my $INSTANCE = $cgi->param( 'hls' );
my $template = HTML::Template->new( filename => "$RealBin/../etc/view.tmpl" );

my @data  = ();
my $ls    = new perfSONAR_PS::Client::LS( { instance => $INSTANCE } );
my @eT    = ( "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/query/xquery/2.0", "http://ogf.org/ns/nmwg/tools/org/perfsonar/service/lookup/discovery/xquery/2.0" );
my @store = ( "LSStore", "LSStore-summary", "LSStore-control" );

foreach my $e ( @eT ) {
    foreach my $s ( @store ) {
        my $MDCOUNT = 0;
        my $DCOUNT = 0;
        my $METADATA = q{};
        my $q        = "declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\";\n/nmwg:store[\@type=\"" . $s . "\"]/nmwg:metadata\n";
        my $result   = $ls->queryRequestLS( { query => $q, eventType => $e, format => 1 } );
        if ( exists $result->{"eventType"} and not( $result->{"eventType"} =~ m/^error/ ) ) {
            my $doc = q{};
            eval { $doc = $parser->parse_string( $result->{"response"} ) if exists $result->{"response"}; };
            if ( $EVAL_ERROR ) {
                $METADATA .= "Cannot parse XML output from service.";
            }
            else {
                my $md = find( $doc->getDocumentElement, ".//nmwg:metadata", 0 );
                foreach my $m ( $md->get_nodelist ) {
                    $METADATA .= escapeString( $m->toString ) . "\n";
                    $MDCOUNT++;
                }
            }
        }
        else {
            if ( exists $result->{"eventType"} and $result->{"eventType"} eq "error.ls.query.ls_output_not_accepted" ) {
                $result = $ls->queryRequestLS( { query => $q, eventType => $e, format => 0 } );
                $result->{"response"} = unescapeString( $result->{"response"} );
                if ( exists $result->{"eventType"} and not( $result->{"eventType"} =~ m/^error/ ) ) {
                    my $doc = q{};
                    eval { $doc = $parser->parse_string( $result->{"response"} ) if exists $result->{"response"}; };
                    if ( $EVAL_ERROR ) {
                        $METADATA .= "Cannot parse XML output from service.";
                    }
                    else {
                        my $md = find( $doc->getDocumentElement, ".//nmwg:metadata", 0 );
                        foreach my $m ( $md->get_nodelist ) {
                            $METADATA .= escapeString( $m->toString ) . "\n";
                            $MDCOUNT++;
                        }
                    }
                }
                else {
                    $METADATA = "EventType:\t" . $result->{'eventType'} . "\nResponse:\t" . $result->{"response"};
                }
            }
            else {
                $METADATA = "EventType:\t" . $result->{'eventType'} . "\nResponse:\t" . $result->{"response"};
            }
        }

        my $DATA = q{};
        $q = "declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\";\n/nmwg:store[\@type=\"" . $s . "\"]/nmwg:data\n";
        $result = $ls->queryRequestLS( { query => $q, eventType => $e, format => 1 } );
        if ( exists $result->{eventType} and not( $result->{eventType} =~ m/^error/ ) ) {
            my $doc = q{};
            eval { $doc = $parser->parse_string( $result->{response} ) if exists $result->{response}; };
            if ( $EVAL_ERROR ) {
                $DATA .= "Cannot parse XML output from service.";
            }
            else {
                my $data = find( $doc->getDocumentElement, ".//nmwg:data", 0 );
                foreach my $d ( $data->get_nodelist ) {
                    $DATA .= escapeString( $d->toString ) . "\n";
                    $DCOUNT++;
                }
            }
        }
        else {
            if ( exists $result->{"eventType"} and $result->{"eventType"} eq "error.ls.query.ls_output_not_accepted" ) {
                $result = $ls->queryRequestLS( { query => $q, eventType => $e, format => 0 } );
                $result->{"response"} = unescapeString( $result->{"response"} );
                if ( exists $result->{"eventType"} and not( $result->{"eventType"} =~ m/^error/ ) ) {
                    my $doc = q{};
                    eval { $doc = $parser->parse_string( $result->{"response"} ) if exists $result->{"response"}; };
                    if ( $EVAL_ERROR ) {
                        $DATA .= "Cannot parse XML output from service.";
                    }
                    else {
                        my $data = find( $doc->getDocumentElement, ".//nmwg:data", 0 );
                        foreach my $d ( $data->get_nodelist ) {
                            $DATA .= escapeString( $d->toString ) . "\n";
                            $DCOUNT++;
                        }
                    }
                }
                else {
                    $DATA = "EventType:\t" . $result->{'eventType'} . "\nResponse:\t" . $result->{"response"};
                }
            }
            else {
                $DATA = "EventType:\t" . $result->{'eventType'} . "\nResponse:\t" . $result->{"response"};
            }
        }

        push @data, { COLLECTION => $e, STORE => $s, METADATA => $METADATA, DATA => $DATA, MDCOUNT => $MDCOUNT, DCOUNT => $DCOUNT };
    }
}

print $cgi->header();

$template->param(
    INSTANCE => $INSTANCE,
    DATA     => \@data
);

print $template->output;

__END__

=head1 SEE ALSO

L<CGI>, L<HTML::Template>, L<XML::LibXML>, L<CGI::Carp>, L<FindBin>, L<English>,
L<perfSONAR_PS::Client::DCN>, L<perfSONAR_PS::Common>

To join the 'perfSONAR-PS Users' mailing list, please visit:

  https://lists.internet2.edu/sympa/info/perfsonar-ps-users

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS/trunk

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2007-2010, Internet2

All rights reserved.

=cut
