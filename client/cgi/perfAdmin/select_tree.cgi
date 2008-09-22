#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

select_tree.cgi - Choose from a list of gLS instances before dumping the 
contents (less resource intensive than 'tree.cgi').  

=head1 DESCRIPTION

Select a gLS instance, dump it's known knowledge of hLS isntance, and then dump
each hLS's knowledge of registered services.

=cut

use XML::LibXML;
use CGI;
use CGI::Ajax;

use lib "/usr/local/perfSONAR-PS/lib";

use perfSONAR_PS::Client::MA;
use perfSONAR_PS::Common qw( extract find );
use perfSONAR_PS::Client::gLS;

my $url    = "http://www.perfsonar.net/gls.root.hints";
my $gls    = perfSONAR_PS::Client::gLS->new( { url => $url } );
my $parser = XML::LibXML->new();

my $cgi = new CGI;
my $pjx = new CGI::Ajax( 'exported_func' => \&show );

print $pjx->build_html( $cgi, \&display );

sub show {
    my ( $load, $root ) = @_;

    my $html = q{};
    unless ( defined $load and $load ) {
        return $html;
    }

    $html .= "<table width=\"100%\" align=\"center\">\n";
    $html .= "<tr>\n";
    $html .= "<th colspan=\"4\" align=\"left\" width=\"100\%\">" . $root . "</th>\n";
    $html .= "</tr>\n";

    my $result = $gls->getLSDiscoverRaw(
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
            if ($value) {

                $html .= "<tr>\n";
                $html .= "<td colspan=\"1\" align=\"left\" width=\"5\%\"><br></td>\n";
                $html .= "<td colspan=\"3\" align=\"left\" width=\"95\%\">" . $value . "</td>\n";
                $html .= "</tr>\n";

                my $result2 = $gls->getLSQueryRaw(
                    {
                        ls => $value,
                        xquery =>
                            "declare namespace perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\";\n declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"; \ndeclare namespace psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\";\n/nmwg:store[\@type=\"LSStore\"]/nmwg:metadata[./*[local-name()='subject']/*[local-name()='service']]"
                    }
                );
                if ( exists $result2->{eventType} and $result2->{eventType} eq "error.ls.querytype_not_suported" ) {
                    $result2 = $gls->getLSQueryRaw(
                        {
                            eventType => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/lookup/xquery/1.0",
                            ls        => $value,
                            xquery =>
                                "declare namespace perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\";\n declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"; \ndeclare namespace psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\";\n/nmwg:store[\@type=\"LSStore\"]/nmwg:metadata[./*[local-name()='subject']/*[local-name()='service']]"
                        }
                    );
                    if ( exists $result2->{eventType} and not( $result2->{eventType} =~ m/^error/ ) ) {
                        my $doc2 = $parser->parse_string( $result2->{response} ) if exists $result2->{response};
                        my $ap2 = find( $doc2->getDocumentElement, ".//psservice:accessPoint", 0 );
                        foreach my $a2 ( $ap2->get_nodelist ) {
                            my $value2 = extract( $a2, 0 );
                            if ($value2) {
                                $html .= "<tr>\n";
                                $html .= "<td colspan=\"1\" align=\"left\" width=\"10\%\"><br></td>\n";
                                $html .= "<td colspan=\"1\" align=\"left\" width=\"10\%\"><br></td>\n";
                                $html .= "<td colspan=\"3\" align=\"left\" width=\"80\%\">" . $value2 . "</td>\n";
                                $html .= "</tr>\n";
                            }
                        }
                        my $ad = find( $doc2->getDocumentElement, ".//nmtb:address[\@type=\"uri\"]", 0 );
                        foreach my $a2 ( $ad->get_nodelist ) {
                            my $value2 = extract( $a2, 0 );
                            ( my $temp = $value2 ) =~ s/^(tcp|udp):\/\///;
                            next if not( $temp =~ m/^\[/ ) and $temp =~ m/^10\./;
                            next if not( $temp =~ m/^\[/ ) and $temp =~ m/^192\.168\./;
                            if ($value2) {
                                $html .= "<tr>\n";
                                $html .= "<td colspan=\"1\" width=\"10\%\" align=\"left\"><br></td>\n";
                                $html .= "<td colspan=\"1\" width=\"10\%\" align=\"left\"><br></td>\n";
                                $html .= "<td colspan=\"3\" width=\"80\%\" align=\"left\">" . $value2 . "</td>\n";
                                $html .= "</tr>\n";
                            }
                        }
                    }
                    elsif ( not exists $result2->{eventType} and exists $result2->{response} and $result2->{response} ) {
                        my $doc2 = $parser->parse_string( $result2->{response} ) if exists $result2->{response};
                        my $ap2 = find( $doc2->getDocumentElement, ".//psservice:accessPoint", 0 );
                        foreach my $a2 ( $ap2->get_nodelist ) {
                            my $value2 = extract( $a2, 0 );
                            if ($value2) {
                                $html .= "<tr>\n";
                                $html .= "<td colspan=\"1\" align=\"left\" width=\"10\%\"><br></td>\n";
                                $html .= "<td colspan=\"1\" align=\"left\" width=\"10\%\"><br></td>\n";
                                $html .= "<td colspan=\"3\" align=\"left\" width=\"80\%\">" . $value2 . "</td>\n";
                                $html .= "</tr>\n";
                            }
                        }
                        my $ad = find( $doc2->getDocumentElement, ".//nmtb:address[\@type=\"uri\"]", 0 );
                        foreach my $a2 ( $ad->get_nodelist ) {
                            my $value2 = extract( $a2, 0 );
                            ( my $temp = $value2 ) =~ s/^(tcp|udp):\/\///;
                            next if not( $temp =~ m/^\[/ ) and $temp =~ m/^10\./;
                            next if not( $temp =~ m/^\[/ ) and $temp =~ m/^192\.168\./;
                            if ($value2) {
                                $html .= "<tr>\n";
                                $html .= "<td colspan=\"1\" width=\"10\%\" align=\"left\"><br></td>\n";
                                $html .= "<td colspan=\"1\" width=\"10\%\" align=\"left\"><br></td>\n";
                                $html .= "<td colspan=\"3\" width=\"80\%\" align=\"left\">" . $value2 . "</td>\n";
                                $html .= "</tr>\n";
                            }
                        }
                    }
                    else {
                        $html .= "<tr>\n";
                        $html .= "<td colspan=\"1\" width=\"10\%\" align=\"left\"><br></td>\n";
                        $html .= "<td colspan=\"1\" width=\"10\%\" align=\"left\"><br></td>\n";
                        $html .= "<td colspan=\"3\" width=\"80\%\" align=\"left\"><font size=\"+1\" color=\"red\">" . $result2->{eventType} . "</font></td>\n";
                        $html .= "</tr>\n";
                    }
                }
                elsif ( exists $result2->{eventType} and not( $result2->{eventType} =~ m/^error/ ) ) {
                    my $doc2 = $parser->parse_string( $result2->{response} ) if exists $result2->{response};
                    my $ap2 = find( $doc2->getDocumentElement, ".//psservice:accessPoint", 0 );
                    foreach my $a2 ( $ap2->get_nodelist ) {
                        my $value2 = extract( $a2, 0 );
                        if ($value2) {
                            $html .= "<tr>\n";
                            $html .= "<td colspan=\"1\" width=\"10\%\" align=\"left\"><br></td>\n";
                            $html .= "<td colspan=\"1\" width=\"10\%\" align=\"left\"><br></td>\n";
                            $html .= "<td colspan=\"3\" width=\"80\%\" align=\"left\">" . $value2 . "</td>\n";
                            $html .= "</tr>\n";
                        }
                    }
                    my $ad = find( $doc2->getDocumentElement, ".//nmtb:address[\@type=\"uri\"]", 0 );
                    foreach my $a2 ( $ad->get_nodelist ) {
                        my $value2 = extract( $a2, 0 );
                        ( my $temp = $value2 ) =~ s/^(tcp|udp):\/\///;
                        next if not( $temp =~ m/^\[/ ) and $temp =~ m/^10\./;
                        next if not( $temp =~ m/^\[/ ) and $temp =~ m/^192\.168\./;
                        if ($value2) {
                            $html .= "<tr>\n";
                            $html .= "<td colspan=\"1\" width=\"10\%\" align=\"left\"><br></td>\n";
                            $html .= "<td colspan=\"1\" width=\"10\%\" align=\"left\"><br></td>\n";
                            $html .= "<td colspan=\"3\" width=\"80\%\" align=\"left\">" . $value2 . "</td>\n";
                            $html .= "</tr>\n";
                        }
                    }
                }
                else {
                    $html .= "<tr>\n";
                    $html .= "<td colspan=\"1\" width=\"10\%\" align=\"left\"><br></td>\n";
                    $html .= "<td colspan=\"1\" width=\"10\%\" align=\"left\"><br></td>\n";
                    $html .= "<td colspan=\"3\" width=\"80\%\" align=\"left\"><font size=\"+1\" color=\"red\">" . $result2->{eventType} . "</font></td>\n";
                    $html .= "</tr>\n";
                }
            }
        }
    }
    else {
        $html .= "<tr>\n";
        $html .= "<td colspan=\"1\" width=\"5\%\" align=\"left\"><br></td>\n";
        $html .= "<td colspan=\"3\" width=\"95\%\" align=\"left\"><font size=\"+1\" color=\"red\">" . $result->{eventType} . "</font></td>\n";
        $html .= "</tr>\n";
    }

    $html .= "</table>\n";

    return $html;
}

# Main Page Display

sub display {
    my $html = $cgi->start_html( -title => 'gLS Contents' );

    $html .= $cgi->h2( { align => "center" }, "gLS Contents" ) . "\n";
    $html .= $cgi->hr( { size => "4", width => "95%" } ) . "\n";

    $html .= $cgi->br;
    $html .= $cgi->br;

    $html .= $cgi->start_table( { border => "2", cellpadding => "1", align => "center", width => "95%" } ) . "\n";

    $html .= $cgi->start_Tr;
    $html .= $cgi->start_th( { align => "center" } );
    $html .= $cgi->h3( { align => "center" }, "gLS Contents" );
    $html .= $cgi->end_td;
    $html .= $cgi->end_Tr;

    $html .= $cgi->start_Tr;
    $html .= $cgi->start_td( { align => "center" } );
    $html .= "<select id=\"query\" name=\"query\" onchange=\"exported_func( ";
    $html .= "['loadQuery', 'query'], ['resultdiv'] );\">\n";
    foreach my $root ( @{ $gls->{ROOTS} } ) {
        $html .= "  <option value=\"" . $root . "\">" . $root . "</option>\n";
    }
    $html .= "</select>\n";

    $html .= "<input type=\"reset\" name=\"query_reset\" ";
    $html .= "value=\"Reset\" onclick=\"exported_func( ";
    $html .= "[], ['resultdiv'] );\">\n";

    $html .= "<input type=\"hidden\" name=\"loadQuery\" ";
    $html .= "id=\"loadQuery\" value=\"1\" />\n";
    $html .= $cgi->end_td;
    $html .= $cgi->end_Tr;

    $html .= $cgi->start_Tr;
    $html .= $cgi->start_td( { align => "left" } );
    $html .= "<div id=\"resultdiv\"></div>\n";
    $html .= $cgi->end_td;
    $html .= $cgi->end_Tr;

    $html .= $cgi->end_table . "\n";

    $html .= $cgi->br;

    $html .= $cgi->hr( { size => "4", width => "95%" } ) . "\n";

    $html .= $cgi->end_html . "\n";
    return $html;
}


__END__

=head1 SEE ALSO

L<>, 

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

Questions and comments can be directed to the author, or the mailing list.  Bugs,
feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

You should have received a copy of the Internet2 Intellectual Property Framework along
with this software.  If not, see <http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2007-2008, Internet2

All rights reserved.

=cut

