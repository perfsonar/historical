#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

completeTree.cgi - Contact each know gLS instances and dump the contents.  

=head1 DESCRIPTION

For each gLS instance, dump it's known knowledge of hLS isntance, and then dump
each hLS's knowledge of registered services.

=cut

use XML::LibXML;
use CGI;
use CGI::Ajax;

#use lib "/usr/local/perfSONAR-PS/lib";
use lib "/home/jason/perfSONAR-PS/lib";

use perfSONAR_PS::Client::MA;
use perfSONAR_PS::Common qw( extract find );
use perfSONAR_PS::Client::gLS;

my $url = "http://www.perfsonar.net/gls.root.hints";

my @hls    = ();
my $gls    = perfSONAR_PS::Client::gLS->new( { url => $url } );
my $parser = XML::LibXML->new();

my @ipaddresses = ();
my @eventTypes  = ();
my @domains     = ();
my @keywords    = ();
my %service     = ();

my $cgi = new CGI;
my $pjx = new CGI::Ajax( 'draw_func' => \&stub, );

print $pjx->build_html( $cgi, \&display );

sub stub {

    #  my() = @_;
    
    # reserved for future use
    
    my $html = q{};
    return $html;
}

sub display {

    my $html = $cgi->start_html( -title => 'perfAdmin - Information Service Listing' );

    $html .= $cgi->start_table( { border => "0", cellpadding => "1", align => "center", width => "75%" } );
    $html .= $cgi->start_Tr;
    $html .= $cgi->start_th( { align => "left", width => "100\%", colspan => "3" } );
    $html .= "Table Of Contents";
    $html .= $cgi->end_th;
    $html .= $cgi->end_Tr;

    $html .= $cgi->start_Tr;
    $html .= $cgi->start_td( { align => "left", width => "5\%" } );
    $html .= "<br>";
    $html .= $cgi->end_td;
    $html .= $cgi->start_td( { colspan => "2", align => "left", width => "95\%" } );
    $html .= "<a href=\"#gls\">gLS Listing</a>";
    $html .= $cgi->end_td;
    $html .= $cgi->end_Tr;

    $html .= $cgi->start_Tr;
    $html .= $cgi->start_td( { align => "left", width => "5\%" } );
    $html .= "<br>";
    $html .= $cgi->end_td;
    $html .= $cgi->start_td( { colspan => "2", align => "left", width => "95\%" } );
    $html .= "<a href=\"#hls\">hLS &amp; Service Listing</a>";
    $html .= $cgi->end_td;
    $html .= $cgi->end_Tr;

    $html .= $cgi->start_Tr;
    $html .= $cgi->start_td( { align => "left", width => "5\%" } );
    $html .= "<br>";
    $html .= $cgi->end_td;
    $html .= $cgi->start_td( { colspan => "2", align => "left", width => "95\%" } );
    $html .= "<a href=\"#missing\">gLS Knowledge Gaps</a>";
    $html .= $cgi->end_td;
    $html .= $cgi->end_Tr;

    $html .= $cgi->end_table;
    $html .= $cgi->br;
    $html .= $cgi->br;
    $html .= $cgi->br;

    unless ( $#{ $gls->{ROOTS} } > -1 ) {
        $html .= "Internal Error: Try again later.";
        $html .= $cgi->br;
        $html .= $cgi->end_html;
        return $html;
    }

    $html .= "<a name=\"gls\" />";
    $html .= $cgi->start_table( { border => "0", cellpadding => "1", align => "center", width => "85%" } );
    $html .= $cgi->start_Tr;
    $html .= $cgi->start_th( { colspan => "4", align => "center", width => "100\%" } );
    $html .= "<font size=\"+1\">List of available gLS Servers</font>";
    $html .= $cgi->end_th;
    $html .= $cgi->end_Tr;
    $html .= $cgi->start_Tr;
    $html .= $cgi->start_th( { colspan => "4", align => "center", width => "100\%" } );
    $html .= "<br><br>";
    $html .= $cgi->end_th;
    $html .= $cgi->end_Tr;
        
    my %hls = ();
    my %matrix = ();
    my $counter = 1;
    foreach my $root ( @{ $gls->{ROOTS} } ) {
        $html .= $cgi->start_Tr;
        $html .= $cgi->start_td( { colspan => "4", align => "left", width => "100\%" } );
        $html .= $counter . ": &nbsp;&nbsp;&nbsp; " . $root;
        $counter++;
        $html .= $cgi->end_td;
        $html .= $cgi->end_Tr;

        my $result = $gls->getLSQueryRaw(
            {
                ls => $root,
                xquery =>
                    "declare namespace perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\";\n declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"; \ndeclare namespace psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\";\n/nmwg:store[\@type=\"LSStore\"]/nmwg:metadata[./perfsonar:subject/psservice:service/psservice:serviceType[text()=\"LS\" or text()=\"hLS\" or text()=\"ls\" or text()=\"hls\"]]"
            }
        );
        if ( exists $result->{eventType} and not( $result->{eventType} =~ m/^error/ ) ) {
            my $doc = $parser->parse_string( $result->{response} ) if exists $result->{response};
            my $ap = find( $doc->getDocumentElement, ".//psservice:accessPoint", 0 );
            foreach my $a ( $ap->get_nodelist ) {
                my $value = extract( $a, 0 );
                if ( $value ) {
                    $hls{$value} = 1;
                    $matrix{$root}{$value} = 1;
                }
            }
        }
    }

    $html .= $cgi->end_table;

    $html .= $cgi->br;
    $html .= $cgi->br;
    $html .= $cgi->br;
        
    $html .= "<a name=\"hls\" />";        
    $html .= $cgi->start_table( { border => "0", cellpadding => "1", align => "center", width => "85%" } );
    $html .= $cgi->start_Tr;
    $html .= $cgi->start_th( { colspan => "4", align => "center", width => "100\%" } );
    $html .= "<font size=\"+1\">List of available hLS Services &amp; Their Registered Services</font>";
    $html .= $cgi->end_th;
    $html .= $cgi->end_Tr;
    $html .= $cgi->start_Tr;
    $html .= $cgi->start_th( { colspan => "4", align => "center", width => "100\%" } );
    $html .= "<br><br>";
    $html .= $cgi->end_th;
    $html .= $cgi->end_Tr;

    foreach my $ls ( keys %hls ) {
        $html .= $cgi->start_Tr;
        $html .= $cgi->start_th( { colspan => "4", align => "left", width => "100\%" } );
        $html .= $ls;
        $html .= $cgi->end_th;
        $html .= $cgi->end_Tr;

        my $result2 = $gls->getLSQueryRaw(
            {
                ls => $ls,
                xquery =>
                    "declare namespace perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\";\n declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"; \ndeclare namespace psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\";\n/nmwg:store[\@type=\"LSStore\"]/nmwg:metadata[./*[local-name()='subject']/*[local-name()='service']]"
            }
        );

        if ( exists $result2->{eventType} and $result2->{eventType} eq "error.ls.querytype_not_suported" ) {
            $result2 = $gls->getLSQueryRaw(
                {
                    eventType => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0",
                    ls        => $ls,
                    xquery    => "declare namespace perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\";\n declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"; \ndeclare namespace psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\";\n/nmwg:store[\@type=\"LSStore\"]/nmwg:metadata[./*[local-name()='subject']/*[local-name()='service']]"
                }
            );
            if ( exists $result2->{eventType} and not( $result2->{eventType} =~ m/^error/ ) ) {
                my $doc2 = $parser->parse_string( $result2->{response} ) if exists $result2->{response};
                my $ap2 = find( $doc2->getDocumentElement, ".//psservice:accessPoint", 0 );
                foreach my $a2 ( $ap2->get_nodelist ) {
                    my $value2 = extract( $a2, 0 );
                    if ($value2) {
                        $html .= $cgi->start_Tr;
                        $html .= $cgi->start_td( { colspan => "1", align => "left", width => "10\%" } );
                        $html .= "<br>";
                        $html .= $cgi->end_td;
                        $html .= $cgi->start_td( { colspan => "1", align => "left", width => "10\%" } );
                        $html .= "<br>";
                        $html .= $cgi->end_td;
                        $html .= $cgi->start_td( { colspan => "3", align => "left", width => "80\%" } );
                        $html .= $value2;
                        $html .= $cgi->end_td;
                        $html .= $cgi->end_Tr;
                    }
                }
                my $ad = find( $doc2->getDocumentElement, ".//nmtb:address[\@type=\"uri\"]", 0 );
                foreach my $a2 ( $ad->get_nodelist ) {
                    my $value2 = extract( $a2, 0 );
                    ( my $temp = $value2 ) =~ s/^(tcp|udp):\/\///;
                    next if not( $temp =~ m/^\[/ ) and $temp =~ m/^10\./;
                    next if not( $temp =~ m/^\[/ ) and $temp =~ m/^192\.168\./;
                    if ($value2) {
                        $html .= $cgi->start_Tr;
                        $html .= $cgi->start_td( { colspan => "1", align => "left", width => "10\%" } );
                        $html .= "<br>";
                        $html .= $cgi->end_td;
                        $html .= $cgi->start_td( { colspan => "1", align => "left", width => "10\%" } );
                        $html .= "<br>";
                        $html .= $cgi->end_td;
                        $html .= $cgi->start_td( { colspan => "3", align => "left", width => "80\%" } );
                        $html .= $value2;
                        $html .= $cgi->end_td;
                        $html .= $cgi->end_Tr;
                    }
                }
            }
            elsif ( not exists $result2->{eventType} and exists $result2->{response} and $result2->{response} ) {
                my $doc2 = $parser->parse_string( $result2->{response} ) if exists $result2->{response};
                my $ap2 = find( $doc2->getDocumentElement, ".//psservice:accessPoint", 0 );
                foreach my $a2 ( $ap2->get_nodelist ) {
                    my $value2 = extract( $a2, 0 );
                    if ($value2) {
                        $html .= $cgi->start_Tr;
                        $html .= $cgi->start_td( { colspan => "1", align => "left", width => "10\%" } );
                        $html .= "<br>";
                        $html .= $cgi->end_td;
                        $html .= $cgi->start_td( { colspan => "1", align => "left", width => "10\%" } );
                        $html .= "<br>";
                        $html .= $cgi->end_td;
                        $html .= $cgi->start_td( { colspan => "3", align => "left", width => "80\%" } );
                        $html .= $value2;
                        $html .= $cgi->end_td;
                        $html .= $cgi->end_Tr;
                    }
                }
                my $ad = find( $doc2->getDocumentElement, ".//nmtb:address[\@type=\"uri\"]", 0 );
                foreach my $a2 ( $ad->get_nodelist ) {
                    my $value2 = extract( $a2, 0 );
                    ( my $temp = $value2 ) =~ s/^(tcp|udp):\/\///;
                    next if not( $temp =~ m/^\[/ ) and $temp =~ m/^10\./;
                    next if not( $temp =~ m/^\[/ ) and $temp =~ m/^192\.168\./;
                    if ($value2) {
                        $html .= $cgi->start_Tr;
                        $html .= $cgi->start_td( { colspan => "1", align => "left", width => "10\%" } );
                        $html .= "<br>";
                        $html .= $cgi->end_td;
                        $html .= $cgi->start_td( { colspan => "1", align => "left", width => "10\%" } );
                        $html .= "<br>";
                        $html .= $cgi->end_td;
                        $html .= $cgi->start_td( { colspan => "3", align => "left", width => "80\%" } );
                        $html .= $value2;
                        $html .= $cgi->end_td;
                        $html .= $cgi->end_Tr;
                    }
                }
            }
            else {
                $html .= $cgi->start_Tr;
                $html .= $cgi->start_td( { colspan => "1", align => "left", width => "10\%" } );
                $html .= "<br>";
                $html .= $cgi->end_td;
                $html .= $cgi->start_td( { colspan => "1", align => "left", width => "10\%" } );
                $html .= "<br>";
                $html .= $cgi->end_td;
                $html .= $cgi->start_td( { colspan => "3", align => "left", width => "80\%" } );
                $html .= "<font size=\"+1\" color=\"red\">ERROR:" . $result2->{eventType} . "</font>";
                $html .= $cgi->end_td;
                $html .= $cgi->end_Tr;
            }
        }
        elsif ( exists $result2->{eventType} and not( $result2->{eventType} =~ m/^error/ ) ) {
            my $doc2 = $parser->parse_string( $result2->{response} ) if exists $result2->{response};
            my $ap2 = find( $doc2->getDocumentElement, ".//psservice:accessPoint", 0 );
            foreach my $a2 ( $ap2->get_nodelist ) {
                my $value2 = extract( $a2, 0 );
                if ($value2) {
                    $html .= $cgi->start_Tr;
                    $html .= $cgi->start_td( { colspan => "1", align => "left", width => "10\%" } );
                    $html .= "<br>";
                    $html .= $cgi->end_td;
                    $html .= $cgi->start_td( { colspan => "1", align => "left", width => "10\%" } );
                    $html .= "<br>";
                    $html .= $cgi->end_td;
                    $html .= $cgi->start_td( { colspan => "3", align => "left", width => "80\%" } );
                    $html .= $value2;
                    $html .= $cgi->end_td;
                    $html .= $cgi->end_Tr;
                }
            }
            my $ad = find( $doc2->getDocumentElement, ".//nmtb:address[\@type=\"uri\"]", 0 );
            foreach my $a2 ( $ad->get_nodelist ) {
                my $value2 = extract( $a2, 0 );

                ( my $temp = $value2 ) =~ s/^(tcp|udp):\/\///;
                next if not( $temp =~ m/^\[/ ) and $temp =~ m/^10\./;
                next if not( $temp =~ m/^\[/ ) and $temp =~ m/^192\.168\./;

                if ($value2) {
                    $html .= $cgi->start_Tr;
                    $html .= $cgi->start_td( { colspan => "1", align => "left", width => "10\%" } );
                    $html .= "<br>";
                    $html .= $cgi->end_td;
                    $html .= $cgi->start_td( { colspan => "1", align => "left", width => "10\%" } );
                    $html .= "<br>";
                    $html .= $cgi->end_td;
                    $html .= $cgi->start_td( { colspan => "3", align => "left", width => "80\%" } );
                    $html .= $value2;
                    $html .= $cgi->end_td;
                    $html .= $cgi->end_Tr;
                }
            }
        }
        else {
            $html .= $cgi->start_Tr;
            $html .= $cgi->start_td( { colspan => "1", align => "left", width => "10\%" } );
            $html .= "<br>";
            $html .= $cgi->end_td;
            $html .= $cgi->start_td( { colspan => "1", align => "left", width => "10\%" } );
            $html .= "<br>";
            $html .= $cgi->end_td;
            if ( ( exists $result2->{eventType} and $result2->{eventType} ) or ( exists $result2->{response} and $result2->{response} ) ) {
                $html .= $cgi->start_td( { colspan => "3", align => "left", width => "80\%" } );
                $html .= "<font size=\"+1\" color=\"red\">" . $result2->{eventType} . " - " . $result2->{response} . "</font>";
                $html .= $cgi->end_td;
            }
            else {
                $html .= $cgi->start_td( { colspan => "3", align => "left", width => "80\%" } );
                $html .= "<font size=\"+1\" color=\"red\">Service cannot be reached.</font>";
                $html .= $cgi->end_td;
            }
            $html .= $cgi->end_Tr;
        }
        
    }


    $html .= $cgi->end_table;

    $html .= $cgi->br;
    $html .= $cgi->br;
    $html .= $cgi->br;
    
    $html .= "<a name=\"missing\" />";
    $html .= $cgi->start_table( { border => "0", cellpadding => "1", align => "center", width => "85%" } );
    $html .= $cgi->start_Tr;
    $html .= $cgi->start_th( { colspan => "4", align => "center", width => "100\%" } );
    $html .= "<font size=\"+1\">List of available gLS Services and the hLS isntances they <b><i><u>DON'T</u> know about (yet)</i></b></font>";
    $html .= $cgi->end_th;
    $html .= $cgi->end_Tr;
    $html .= $cgi->start_Tr;
    $html .= $cgi->start_th( { colspan => "4", align => "center", width => "100\%" } );
    $html .= "<br><br>";
    $html .= $cgi->end_th;
    $html .= $cgi->end_Tr;
    
    foreach my $root ( @{ $gls->{ROOTS} } ) {
        $html .= $cgi->start_Tr;
        $html .= $cgi->start_th( { colspan => "4", align => "left", width => "100\%" } );
        $html .= $root;
        $html .= $cgi->end_th;
        $html .= $cgi->end_Tr;
        
        my $flag = 0;
        foreach my $ls ( keys %hls ) {
            unless (exists $matrix{$root}{$ls} and $matrix{$root}{$ls} == 1 ) {
                $html .= $cgi->start_Tr;
                $html .= $cgi->start_td( { colspan => "1", align => "left", width => "10\%" } );
                $html .= "<br>";
                $html .= $cgi->end_td;
                $html .= $cgi->start_td( { colspan => "1", align => "left", width => "10\%" } );
                $html .= "<br>";
                $html .= $cgi->end_td;
                $html .= $cgi->start_td( { colspan => "3", align => "left", width => "80\%" } );
                $html .= "<font size=\"+1\" color=\"red\">has no record of ".$ls."</font>";
                $html .= $cgi->end_td;
                $html .= $cgi->end_Tr;
                $flag++;
            }
        }
        if ( not $flag ) {
            $html .= $cgi->start_Tr;
            $html .= $cgi->start_td( { colspan => "1", align => "left", width => "10\%" } );
            $html .= "<br>";
            $html .= $cgi->end_td;
            $html .= $cgi->start_td( { colspan => "1", align => "left", width => "10\%" } );
            $html .= "<br>";
            $html .= $cgi->end_td;
            $html .= $cgi->start_td( { colspan => "3", align => "left", width => "80\%" } );
            $html .= "<font size=\"+1\" color=\"green\">has a record of all hLS instances</font>";
            $html .= $cgi->end_td;
            $html .= $cgi->end_Tr;
        }
    }
    
    $html .= $cgi->end_table;

    $html .= $cgi->br;

    $html .= $cgi->end_html;
    return $html;
}


__END__

=head1 SEE ALSO

L<XML::LibXML>, L<CGI>, L<CGI::Ajax>, L<perfSONAR_PS::Client::MA>,
L<perfSONAR_PS::Common>, L<perfSONAR_PS::Client::gLS>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.  Bugs,
feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id: tree.cgi 2257 2008-09-30 13:49:36Z zurawski $

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2007-2008, Internet2

All rights reserved.

=cut

