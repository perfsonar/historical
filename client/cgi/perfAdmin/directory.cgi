#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

directory.cgi - Script that takes a global inventory of the perfSONAR
information space and presents the results.

=head1 DESCRIPTION

Using the gLS infrastructure, locate all available perfSONAR services and
display the results in a tabulated form.  Using links to GUIs, present the
data for the viewer.

=cut

use XML::LibXML;
use Date::Manip;
use CGI;
use CGI::Ajax;

use Socket;
use POSIX;
use IO::Socket;
use IO::Socket::INET;
use IO::Interface qw(:flags);

use lib "/home/zurawski/perfSONAR-PS/lib";
#use lib "/usr/local/perfSONAR-PS/lib";

use perfSONAR_PS::Client::MA;
use perfSONAR_PS::Client::gLS;
use perfSONAR_PS::Common qw( extract find );

my $url = "http://www.perfsonar.net/gls.root.hints";

my @hls    = ();
my $gls    = perfSONAR_PS::Client::gLS->new( { url => $url } );
my $parser = XML::LibXML->new();

my $cgi = new CGI;
my $pjx = new CGI::Ajax(
    'draw_func' => \&queryMA,
    'reset'     => \&clear
);

print $pjx->build_html( $cgi, \&display );

sub clear {
    return;
}

sub queryMA {
    my ( $service, $eventType ) = @_;
    my $html = q{};

    unless ( $service and $eventType ) {
        $html .= "<br><h3 align=\"center\">Internal Error: Data cannot be displayed.</h3><br><br>";
        return $html;
    }
    $eventType =~ s/(\s|\n)*//g;

    my $ma = new perfSONAR_PS::Client::MA( { instance => $service } );

    my $subject;
    my @eventTypes = ();
    push @eventTypes, $eventType;
    if ( $eventType eq "http://ggf.org/ns/nmwg/characteristic/utilization/2.0" ) {
        $subject = "    <netutil:subject xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\" id=\"s\">\n";
        $subject .= "      <nmwgt:interface xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\" />\n";
        $subject .= "    </netutil:subject>\n";
    }
    elsif ( $eventType eq "http://ggf.org/ns/nmwg/tools/iperf/2.0" or $eventType eq "http://ggf.org/ns/nmwg/characteristics/bandwidth/acheiveable/2.0" ) {
        $subject = "    <iperf:subject xmlns:iperf=\"http://ggf.org/ns/nmwg/tools/iperf/2.0/\" id=\"subject\">\n";
        $subject .= "      <nmwgt:endPointPair xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\" />\n";
        $subject .= "    </iperf:subject>\n";
    }
    elsif ( $eventType eq "http://ggf.org/ns/nmwg/tools/owamp/2.0" or $eventType eq "http://ggf.org/ns/nmwg/characteristic/delay/summary/20070921" ) {
        $subject = "    <owamp:subject xmlns:owamp=\"http://ggf.org/ns/nmwg/tools/owamp/2.0/\" id=\"subject\">\n";
        $subject .= "      <nmwgt:endPointPair xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\" />\n";
        $subject .= "    </owamp:subject>\n";
    }
    elsif ( $eventType eq "http://ggf.org/ns/nmwg/tools/pinger/2.0/" or $eventType eq "http://ggf.org/ns/nmwg/tools/pinger/2.0" ) {
        $subject = "    <pinger:subject xmlns:pinger=\"http://ggf.org/ns/nmwg/tools/pinger/2.0/\" id=\"subject\">\n";
        $subject .= "      <nmwgt:endPointPair xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\" />\n";
        $subject .= "    </pinger:subject>\n";
    }
    else {
        $html .= "<center><h2><b><i>" . $eventType . "</b></i> is not yet supported.</h2></center>\n";
        $html .= $cgi->br;
        return $html;
    }

    my $parser = XML::LibXML->new();
    my $result = $ma->metadataKeyRequest(
        {
            subject    => $subject,
            eventTypes => \@eventTypes
        }
    );

    unless ( $#{ $result->{"metadata"} } > -1 ) {
        $html .= "<center><h2>MA <b><i>" . $service . "</i></b> experienced an error, service may be unreachable.</h2></center>\n";
        $html .= $cgi->br;
        return $html;
    }

    my $metadata = $parser->parse_string( $result->{"metadata"}->[0] );
    my $et = extract( find( $metadata->getDocumentElement, ".//nmwg:eventType", 1 ), 0 );

    if ( $et eq "error.ma.storage" ) {
        $html .= "<center><h2>MA <b><i>" . $service . "</i></b> experienced an error, check configuration and contents of store file.</h2></center>\n";
        $html .= $cgi->br;
        return $html;
    }
    else {
        if ( $eventType eq "http://ggf.org/ns/nmwg/characteristic/utilization/2.0" ) {

            my %lookup = ();
            foreach my $d ( @{ $result->{"data"} } ) {
                my $data          = $parser->parse_string($d);
                my $metadataIdRef = $data->getDocumentElement->getAttribute("metadataIdRef");
                my $key           = extract( find( $data->getDocumentElement, ".//nmwg:parameter[\@name=\"maKey\"]", 1 ), 0 );
                $lookup{$metadataIdRef} = $key if $key and $metadataIdRef;
            }

            my %list = ();
            foreach my $md ( @{ $result->{"metadata"} } ) {
                my $metadata   = $parser->parse_string($md);
                my $metadataId = $metadata->getDocumentElement->getAttribute("id");
                my $dir        = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:interface/nmwgt:direction", 1 ), 0 );
                my $host       = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:interface/nmwgt:hostName", 1 ), 0 );
                my $name       = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:interface/nmwgt:ifName", 1 ), 0 );
                if ( $list{$host}{$name} ) {
                    if ( $dir eq "in" ) {
                        $list{$host}{$name}->{"key1"} = $lookup{$metadataId};
                    }
                    else {
                        $list{$host}{$name}->{"key2"} = $lookup{$metadataId};
                    }
                }
                else {
                    my %temp = ();
                    if ( $dir eq "in" ) {
                        $temp{"key1"} = $lookup{$metadataId};
                    }
                    else {
                        $temp{"key2"} = $lookup{$metadataId};
                    }
                    $temp{"hostName"}      = $host;
                    $temp{"ifName"}        = $name;
                    $temp{"ipAddress"}     = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:interface/nmwgt:ipAddress", 1 ), 0 );
                    $temp{"ifDescription"} = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:interface/nmwgt:ifDescription", 1 ), 0 );
                    $temp{"ifAddress"}     = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:interface/nmwgt:ifAddress", 1 ), 0 );
                    $temp{"capacity"}      = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:interface/nmwgt:capacity", 1 ), 0 );
                    $list{$host}{$name}    = \%temp;
                }
            }

            $html .= $cgi->start_table( { border => "2", cellpadding => "1", align => "center", width => "100%" } );

            $html .= $cgi->start_Tr;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Address\n";
            $html .= $cgi->end_th;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Host\n";
            $html .= $cgi->end_th;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "ifName\n";
            $html .= $cgi->end_th;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Descr.\n";
            $html .= $cgi->end_th;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "ifAddress\n";
            $html .= $cgi->end_th;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Capacity\n";
            $html .= $cgi->end_th;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Graph\n";
            $html .= $cgi->end_th;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Flash Graph\n";
            $html .= $cgi->end_th;
            $html .= $cgi->end_Tr;

            my $counter = 0;
            foreach my $host ( sort keys %list ) {
                foreach my $name ( sort keys %{ $list{$host} } ) {
                    $html .= $cgi->start_Tr;
                    $html .= $cgi->start_td( { align => "center" } );
                    $html .= $list{$host}{$name}->{"ipAddress"}, "\n";
                    $html .= $cgi->end_td;
                    $html .= $cgi->start_td( { align => "center" } );
                    $html .= $list{$host}{$name}->{"hostName"}, "\n";
                    $html .= $cgi->end_td;
                    $html .= $cgi->start_td( { align => "center" } );
                    $html .= $list{$host}{$name}->{"ifName"}, "\n";
                    $html .= $cgi->end_td;
                    $html .= $cgi->start_td( { align => "center" } );
                    $html .= $list{$host}{$name}->{"ifDescription"}, "\n";
                    $html .= $cgi->end_td;
                    $html .= $cgi->start_td( { align => "center" } );
                    $html .= $list{$host}{$name}->{"ifAddress"}, "\n";
                    $html .= $cgi->end_td;
                    $html .= $cgi->start_td( { align => "center" } );
                    $html .= eval( $list{$host}{$name}->{"capacity"} / 1000000 ) . " M\n";
                    $html .= $cgi->end_td;

                    $html .= $cgi->start_td( { align => "center" } );
                    $html .= "<input type=\"submit\" value=\"Graph\" id=\"if." . $counter . "\" ";
                    $html .= "name=\"if." . $counter . "\" onClick=\"window.open(";
                    $html .= "'utilizationGraph.cgi?url=" . $service . "&key1=" . $list{$host}{$name}->{"key1"};
                    $html .= "&key2=" . $list{$host}{$name}->{"key2"} . "','graphwindow." . $counter . "','width=950,";
                    $html .= "height=450,status=yes,scrollbars=yes,resizable=yes')\" />\n";
                    $html .= $cgi->end_td;

                    $html .= $cgi->start_td( { align => "center" } );
                    $html .= "<input type=\"submit\" value=\"Graph\" id=\"if2." . $counter . "\" ";
                    $html .= "name=\"if2." . $counter . "\" onClick=\"window.open(";
                    $html .= "'utilizationGraphFlash.cgi?url=" . $service . "&key1=" . $list{$host}{$name}->{"key1"};
                    $html .= "&key2=" . $list{$host}{$name}->{"key2"} . "','graphwindow." . $counter . "','width=950,";
                    $html .= "height=450,status=yes,scrollbars=yes,resizable=yes')\" />\n";
                    $html .= $cgi->end_td;
                    $html .= $cgi->end_Tr;

                    $counter++;
                }
            }
        }
        elsif ( $eventType eq "http://ggf.org/ns/nmwg/tools/iperf/2.0" or $eventType eq "http://ggf.org/ns/nmwg/characteristics/bandwidth/acheiveable/2.0" ) {

            my %lookup = ();
            foreach my $d ( @{ $result->{"data"} } ) {
                my $data          = $parser->parse_string($d);
                my $metadataIdRef = $data->getDocumentElement->getAttribute("metadataIdRef");
                my $key           = extract( find( $data->getDocumentElement, ".//nmwg:parameter[\@name=\"maKey\"]", 1 ), 0 );
                $lookup{$metadataIdRef} = $key if $key and $metadataIdRef;
            }

            my %list = ();
            foreach my $md ( @{ $result->{"metadata"} } ) {
                my $metadata   = $parser->parse_string($md);
                my $metadataId = $metadata->getDocumentElement->getAttribute("id");

                my $src  = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:endPointPair/nmwgt:src",                           1 ), 0 );
                my $dst  = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:endPointPair/nmwgt:dst",                           1 ), 0 );
                my $type = extract( find( $metadata->getDocumentElement, "./*[local-name()='parameters']/*[local-name()='parameter' and \@name=\"protocol\"]", 1 ), 0 );

                my %temp = ();
                $temp{"key"}             = $lookup{$metadataId};
                $temp{"src"}             = $src;
                $temp{"dst"}             = $dst;
                $temp{"type"}            = $type;
                $list{$src}{$dst}{$type} = \%temp;
            }

            $html .= $cgi->start_table( { border => "2", cellpadding => "1", align => "center", width => "100%" } );

            $html .= $cgi->start_Tr;

            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Source Address\n";
            $html .= $cgi->end_th;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Source Host\n";
            $html .= $cgi->end_th;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Destination Address\n";
            $html .= $cgi->end_th;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Destination Host\n";
            $html .= $cgi->end_th;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Protocol\n";
            $html .= $cgi->end_th;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Graph\n";
            $html .= $cgi->end_th;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Flash Graph\n";
            $html .= $cgi->end_th;
            $html .= $cgi->end_Tr;

            my $counter = 0;
            foreach my $src ( sort keys %list ) {
                foreach my $dst ( sort keys %{ $list{$src} } ) {
                    foreach my $type ( sort keys %{ $list{$src}{$dst} } ) {
                        $html .= $cgi->start_Tr;

                        # src ip
                        $html .= $cgi->start_td( { align => "center" } );
                        $html .= $list{$src}{$dst}{$type}->{"src"}, "\n";
                        $html .= $cgi->end_td;

                        # src host
                        my $display = $list{$src}{$dst}{$type}->{"src"};
                        $display =~ s/:.*$//;
                        my $iaddr = Socket::inet_aton($display);
                        my $shost = gethostbyaddr( $iaddr, Socket::AF_INET );
                        $html .= $cgi->start_td( { align => "center" } );
                        if ($shost) {
                            $html .= $shost . "\n";
                        }
                        else {
                            $html .= $list{$src}{$dst}{$type}->{"src"} . "\n";
                        }
                        $html .= $cgi->end_td;

                        # dst ip
                        $html .= $cgi->start_td( { align => "center" } );
                        $html .= $list{$src}{$dst}{$type}->{"dst"} . "\n";
                        $html .= $cgi->end_td;

                        # dst host
                        my $display2 = $list{$src}{$dst}{$type}->{"dst"};
                        $display2 =~ s/:.*$//;
                        my $iaddr2 = Socket::inet_aton($display2);
                        my $dhost = gethostbyaddr( $iaddr2, Socket::AF_INET );
                        $html .= $cgi->start_td( { align => "center" } );
                        if ($dhost) {
                            $html .= $dhost . "\n";
                        }
                        else {
                            $html .= $list{$src}{$dst}{$type}->{"dst"} . "\n";
                        }
                        $html .= $cgi->end_td;

                        $html .= $cgi->start_td( { align => "center" } );
                        $html .= $list{$src}{$dst}{$type}->{"type"} . "\n";
                        $html .= $cgi->end_td;

                        $html .= $cgi->start_td( { align => "center" } );
                        $html .= "<input type=\"submit\" value=\"Graph\" id=\"if." . $counter . "\" ";
                        $html .= "name=\"if." . $counter . "\" onClick=\"window.open(";
                        $html .= "'bandwidthGraph.cgi?url=" . $service . "&key=" . $list{$src}{$dst}{$type}->{"key"} . "','graphwindow." . $counter . "','width=950,";
                        $html .= "height=450,status=yes,scrollbars=yes,resizable=yes')\" />\n";
                        $html .= $cgi->end_td;

                        $html .= $cgi->start_td( { align => "center" } );
                        $html .= "<input type=\"submit\" value=\"Graph\" id=\"if2." . $counter . "\" ";
                        $html .= "name=\"if2." . $counter . "\" onClick=\"window.open(";
                        $html .= "'bandwidthGraphFlash.cgi?url=" . $service . "&key=" . $list{$src}{$dst}{$type}->{"key"} . "','graphwindow." . $counter . "','width=950,";
                        $html .= "height=450,status=yes,scrollbars=yes,resizable=yes')\" />\n";
                        $html .= $cgi->end_td;

                        $html .= $cgi->end_Tr;

                        $counter++;
                    }
                }
            }
        }
        elsif ( $eventType eq "http://ggf.org/ns/nmwg/tools/owamp/2.0" or $eventType eq "http://ggf.org/ns/nmwg/characteristic/delay/summary/20070921" ) {

            my %lookup = ();
            foreach my $d ( @{ $result->{"data"} } ) {
                my $data          = $parser->parse_string($d);
                my $metadataIdRef = $data->getDocumentElement->getAttribute("metadataIdRef");
                my $key           = extract( find( $data->getDocumentElement, ".//nmwg:parameter[\@name=\"maKey\"]", 1 ), 0 );
                $lookup{$metadataIdRef} = $key if $key and $metadataIdRef;
            }

            my %list = ();
            foreach my $md ( @{ $result->{"metadata"} } ) {
                my $metadata   = $parser->parse_string($md);
                my $metadataId = $metadata->getDocumentElement->getAttribute("id");

                my $src = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:endPointPair/nmwgt:src", 1 ), 0 );
                my $dst = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:endPointPair/nmwgt:dst", 1 ), 0 );

                my %temp = ();
                $temp{"key"}      = $lookup{$metadataId};
                $temp{"src"}      = $src;
                $temp{"dst"}      = $dst;
                $list{$src}{$dst} = \%temp;
            }

            $html .= $cgi->start_table( { border => "2", cellpadding => "1", align => "center", width => "100%" } );

            $html .= $cgi->start_Tr;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Source Address\n";
            $html .= $cgi->end_th;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Source Host\n";
            $html .= $cgi->end_th;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Destination Address\n";
            $html .= $cgi->end_th;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Destination Host\n";
            $html .= $cgi->end_th;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Graph\n";
            $html .= $cgi->end_th;
            $html .= $cgi->end_Tr;

            my $counter = 0;
            foreach my $src ( sort keys %list ) {
                foreach my $dst ( sort keys %{ $list{$src} } ) {
                    $html .= $cgi->start_Tr;

                    $html .= $cgi->start_td( { align => "center" } );
                    $html .= $list{$src}{$dst}->{"src"}, "\n";
                    $html .= $cgi->end_td;
                    my $display = $list{$src}{$dst}->{"src"};
                    $display =~ s/:.*$//;
                    my $iaddr = Socket::inet_aton($display);
                    my $shost = gethostbyaddr( $iaddr, Socket::AF_INET );
                    $html .= $cgi->start_td( { align => "center" } );
                    if ($shost) {
                        $html .= $shost . "\n";
                    }
                    else {
                        $html .= $list{$src}{$dst}->{"src"}, "\n";
                    }
                    $html .= $cgi->end_td;

                    $html .= $cgi->start_td( { align => "center" } );
                    $html .= $list{$src}{$dst}->{"dst"}, "\n";
                    $html .= $cgi->end_td;
                    my $display2 = $list{$src}{$dst}->{"dst"};
                    $display2 =~ s/:.*$//;
                    my $iaddr2 = Socket::inet_aton($display2);
                    my $dhost = gethostbyaddr( $iaddr2, Socket::AF_INET );
                    $html .= $cgi->start_td( { align => "center" } );
                    if ($dhost) {
                        $html .= $dhost . "\n";
                    }
                    else {
                        $html .= $list{$src}{$dst}->{"dst"}, "\n";
                    }
                    $html .= $cgi->end_td;

                    $html .= $cgi->start_td( { align => "center" } );
                    $html .= "<input type=\"submit\" value=\"Graph\" id=\"if." . $counter . "\" ";
                    $html .= "name=\"if." . $counter . "\" onClick=\"window.open(";
                    $html .= "'delayGraph.cgi?url=" . $service . "&key=" . $list{$src}{$dst}->{"key"} . "','graphwindow." . $counter . "','width=950,";
                    $html .= "height=450,status=yes,scrollbars=yes,resizable=yes')\" />\n";
                    $html .= $cgi->end_td;
                    $html .= $cgi->end_Tr;

                    $counter++;
                }
            }
        }
        elsif ( $eventType eq "http://ggf.org/ns/nmwg/tools/pinger/2.0/" or $eventType eq "http://ggf.org/ns/nmwg/tools/pinger/2.0" ) {

            my %lookup = ();
            foreach my $d ( @{ $result->{"data"} } ) {
                my $data          = $parser->parse_string($d);
                my $metadataIdRef = $data->getDocumentElement->getAttribute("metadataIdRef");
                my $key           = extract( find( $data->getDocumentElement, ".//nmwg:parameter[\@name=\"maKey\"]", 1 ), 0 );
                $lookup{$metadataIdRef} = $key if $key and $metadataIdRef;
            }

            my %list = ();
            foreach my $md ( @{ $result->{"metadata"} } ) {
                my $metadata   = $parser->parse_string($md);
                my $metadataId = $metadata->getDocumentElement->getAttribute("id");

                my $src = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:endPointPair/nmwgt:src", 1 ), 0 );
                my $dst = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:endPointPair/nmwgt:dst", 1 ), 0 );

                my %temp = ();
                $temp{"key"}      = $lookup{$metadataId};
                $temp{"src"}      = $src;
                $temp{"dst"}      = $dst;
                $list{$src}{$dst} = \%temp;
            }

            $html .= $cgi->start_table( { border => "2", cellpadding => "1", align => "center", width => "100%" } );

            $html .= $cgi->start_Tr;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Source Address\n";
            $html .= $cgi->end_th;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Source Host\n";
            $html .= $cgi->end_th;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Destination Address\n";
            $html .= $cgi->end_th;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Destination Host\n";
            $html .= $cgi->end_th;
            $html .= $cgi->start_th( { align => "center" } );
            $html .= "Graph\n";
            $html .= $cgi->end_th;
            $html .= $cgi->end_Tr;

            my $counter = 0;
            foreach my $src ( sort keys %list ) {
                foreach my $dst ( sort keys %{ $list{$src} } ) {
                    $html .= $cgi->start_Tr;

                    # xxx 7/30/08
                    # needs fixed

                    # src ip
                    $html .= $cgi->start_td( { align => "center" } );
                    my $packed_ip = gethostbyname( $list{$src}{$dst}->{"src"} );
                    if ( defined $packed_ip ) {
                        my $ip_address = inet_ntoa($packed_ip);
                        $html .= Socket::inet_ntoa($packed_ip) . "\n";
                    }
                    else {
                        $html .= $list{$src}{$dst}->{"src"} . "\n";
                    }
                    $html .= $cgi->end_td;

                    # src host
                    $html .= $cgi->start_td( { align => "center" } );
                    $html .= $list{$src}{$dst}->{"src"} . "\n";
                    $html .= $cgi->end_td;

                    # dst ip
                    $html .= $cgi->start_td( { align => "center" } );
                    my $packed_ip = gethostbyname( $list{$src}{$dst}->{"dst"} );
                    if ( defined $packed_ip ) {
                        my $ip_address = inet_ntoa($packed_ip);
                        $html .= Socket::inet_ntoa($packed_ip) . "\n";
                    }
                    else {
                        $html .= $list{$src}{$dst}->{"dst"} . "\n";
                    }
                    $html .= $cgi->end_td;

                    # dst host
                    $html .= $cgi->start_td( { align => "center" } );
                    $html .= $list{$src}{$dst}->{"dst"} . "\n";
                    $html .= $cgi->end_td;

                    $html .= $cgi->start_td( { align => "center" } );
                    $html .= "<input type=\"submit\" value=\"Graph\" id=\"if." . $counter . "\" ";
                    $html .= "name=\"if." . $counter . "\" onClick=\"window.open(";

                    #$html .= "'http://tukki.fnal.gov/pinger/pingerUI.pl?ma=";
                    $html .= "'./pinger/index.cgi?ma=";
                    $html .= $service . "&get_it=jh34587wuhlkh789hbyf78343gort03idjuhf3785t0gfgofbf78o4348orgofg7o4fg7&link=";
                    $html .= $list{$src}{$dst}->{"src"} . ":" . $list{$src}{$dst}->{"dst"} . ":1000";

                    my $p_time = time - 43200;
                    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime($p_time);
                    my $p_start = sprintf "%04d-%02d-%02dT%02d:%02d:%02d", ( $year + 1900 ), ( $mon + 1 ), $mday, $hour, $min, $sec;
                    $p_time += 43200;
                    ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime($p_time);
                    my $p_end = sprintf "%04d-%02d-%02dT%02d:%02d:%02d", ( $year + 1900 ), ( $mon + 1 ), $mday, $hour, $min, $sec;
                    $html .= "&time_start=" . $p_start;
                    $html .= "&time_end=" . $p_end;

                    $html .= "&upper_rtt=auto&gmt_offset=-5&gtype=rt&gpresent=lines'";
                    $html .= ",'graphwindow." . $counter . "','width=460,";
                    $html .= "height=250,status=yes,scrollbars=yes,resizable=yes')\" />\n";
                    $html .= $cgi->end_td;

                    $html .= $cgi->end_Tr;

                    $counter++;
                }
            }
        }
        else {
            $html .= "<center><h2><b><i>" . $eventType . "</b></i> is not yet supported.</h2></center>\n";
            $html .= $cgi->br;
            return $html;
        }
    }

    return $html;
}

sub display {

    my $html = $cgi->start_html( -title => 'perfAdmin' );

    $html .= $cgi->br;
    $html .= "<h2 align=\"center\">perfSONAR Global Service and Data View</h2>\n";
    $html .= $cgi->br;

    unless ( $#{ $gls->{ROOTS} } > -1 ) {
        $html .= "Internal Error: Try again later.";
        $html .= $cgi->br;
        $html .= $cgi->end_html;
        return $html;
    }

    my %etTotal = ();

    # staking our claim on a single gLS query (cuts down on time until caching is here
    my $root = $gls->{ROOTS}->[0];

    my $result = $gls->getLSDiscoverRaw( { ls => $root, xquery => "declare namespace perfsonar=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/\";\n declare namespace nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"; \ndeclare namespace psservice=\"http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/\";\n/nmwg:store[\@type=\"LSStore\"]/nmwg:data/nmwg:metadata/nmwg:eventType" } );
    if ( exists $result->{eventType} and not( $result->{eventType} =~ m/^error/ ) ) {
        my $doc = $parser->parse_string( $result->{response} ) if exists $result->{response};
        my $eT = find( $doc->getDocumentElement, ".//nmwg:eventType", 0 );
        foreach my $e ( $eT->get_nodelist ) {
            my $et_value = extract( $e, 0 );
            $etTotal{$et_value} = 1 if $et_value;
        }
    }
    elsif ( exists $result->{eventType} ) {
        $html .= $cgi->start_table( { border => "2", cellpadding => "1", align => "center", width => "85%" } );
        $html .= $cgi->start_Tr;
        $html .= $cgi->start_td( { colspan => "3", align => "left", width => "95\%" } );
        $html .= "<font size=\"+1\" color=\"red\">" . $result->{eventType} . "</font>";
        $html .= $cgi->end_td;
        $html .= $cgi->end_Tr;
        $html .= $cgi->end_table;
        return $html;
    }
    else {
        $html .= $cgi->start_table( { border => "2", cellpadding => "1", align => "center", width => "85%" } );
        $html .= $cgi->start_Tr;
        $html .= $cgi->start_td( { colspan => "3", align => "left", width => "95\%" } );
        $html .= "<font size=\"+1\" color=\"red\">Unknown Error - Aborting</font>";
        $html .= $cgi->end_td;
        $html .= $cgi->end_Tr;
        $html .= $cgi->end_table;
        return $html;
    }

    # make the cache here...

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
    $html .= "<a href=\"#daemons\">Measurement Tools</a>";
    $html .= $cgi->end_td;
    $html .= $cgi->end_Tr;
    foreach my $e ( keys %etTotal ) {

        if ( $e eq "http://ggf.org/ns/nmwg/tools/ndt/1.0" ) {
            $html .= $cgi->start_Tr;
            $html .= $cgi->start_td( { align => "left", width => "5\%" } );
            $html .= "<br>";
            $html .= $cgi->end_td;
            $html .= $cgi->start_td( { align => "left", width => "5\%" } );
            $html .= "<br>";
            $html .= $cgi->end_td;
            $html .= $cgi->start_td( { align => "left", width => "90\%" } );
            $html .= "<a href=\"#ndt_daemon\">NDT Daemons</a>";
            $html .= $cgi->end_td;
            $html .= $cgi->end_Tr;
        }
        elsif ( $e eq "http://ggf.org/ns/nmwg/tools/npad/1.0" ) {
            $html .= $cgi->start_Tr;
            $html .= $cgi->start_td( { align => "left", width => "5\%" } );
            $html .= "<br>";
            $html .= $cgi->end_td;
            $html .= $cgi->start_td( { align => "left", width => "5\%" } );
            $html .= "<br>";
            $html .= $cgi->end_td;
            $html .= $cgi->start_td( { align => "left", width => "90\%" } );
            $html .= "<a href=\"#npad_daemon\">NPAD Daemons</a>";
            $html .= $cgi->end_td;
            $html .= $cgi->end_Tr;
        }
        elsif ( $e eq "http://ggf.org/ns/nmwg/tools/owamp/1.0" ) {
            $html .= $cgi->start_Tr;
            $html .= $cgi->start_td( { align => "left", width => "5\%" } );
            $html .= "<br>";
            $html .= $cgi->end_td;
            $html .= $cgi->start_td( { align => "left", width => "5\%" } );
            $html .= "<br>";
            $html .= $cgi->end_td;
            $html .= $cgi->start_td( { align => "left", width => "90\%" } );
            $html .= "<a href=\"#owamp_daemon\">OWAMP Daemons</a>";
            $html .= $cgi->end_td;
            $html .= $cgi->end_Tr;
        }
        elsif ( $e eq "http://ggf.org/ns/nmwg/tools/bwctl/1.0" ) {
            $html .= $cgi->start_Tr;
            $html .= $cgi->start_td( { align => "left", width => "5\%" } );
            $html .= "<br>";
            $html .= $cgi->end_td;
            $html .= $cgi->start_td( { align => "left", width => "5\%" } );
            $html .= "<br>";
            $html .= $cgi->end_td;
            $html .= $cgi->start_td( { align => "left", width => "90\%" } );
            $html .= "<a href=\"#bwctl_daemon\">BWCTL Daemons</a>";
            $html .= $cgi->end_td;
            $html .= $cgi->end_Tr;
        }
    }
    $html .= $cgi->start_Tr;
    $html .= $cgi->start_td( { align => "left", width => "5\%" } );
    $html .= "<br>";
    $html .= $cgi->end_td;
    $html .= $cgi->start_td( { colspan => "2", align => "left", width => "95\%" } );
    $html .= "<a href=\"#ps\">perfSONAR Services</a>";
    $html .= $cgi->end_td;
    $html .= $cgi->end_Tr;

    foreach my $e ( keys %etTotal ) {
        if ( $e eq "http://ggf.org/ns/nmwg/characteristic/utilization/2.0" or $e eq "http://ggf.org/ns/nmwg/tools/snmp/2.0" ) {
            $html .= $cgi->start_Tr;
            $html .= $cgi->start_td( { align => "left", width => "5\%" } );
            $html .= "<br>";
            $html .= $cgi->end_td;
            $html .= $cgi->start_td( { align => "left", width => "5\%" } );
            $html .= "<br>";
            $html .= $cgi->end_td;
            $html .= $cgi->start_td( { align => "left", width => "90\%" } );
            $html .= "<a href=\"#utilization_service\">SNMP MA (Utilization)</a>";
            $html .= $cgi->end_td;
            $html .= $cgi->end_Tr;
        }
        elsif ( $e eq "http://ggf.org/ns/nmwg/characteristic/delay/summary/20070921" or $e eq "http://ggf.org/ns/nmwg/tools/owamp/2.0" ) {
            $html .= $cgi->start_Tr;
            $html .= $cgi->start_td( { align => "left", width => "5\%" } );
            $html .= "<br>";
            $html .= $cgi->end_td;
            $html .= $cgi->start_td( { align => "left", width => "5\%" } );
            $html .= "<br>";
            $html .= $cgi->end_td;
            $html .= $cgi->start_td( { align => "left", width => "90\%" } );
            $html .= "<a href=\"#owamp_service\">perfSONAR-BUOY (OWAMP Data)</a>";
            $html .= $cgi->end_td;
            $html .= $cgi->end_Tr;
        }
        elsif ( $e eq "http://ggf.org/ns/nmwg/characteristics/bandwidth/acheiveable/2.0" or $e eq "http://ggf.org/ns/nmwg/characteristics/bandwidth/achieveable/2.0" or $e eq "http://ggf.org/ns/nmwg/tools/iperf/2.0" ) {
            $html .= $cgi->start_Tr;
            $html .= $cgi->start_td( { align => "left", width => "5\%" } );
            $html .= "<br>";
            $html .= $cgi->end_td;
            $html .= $cgi->start_td( { align => "left", width => "5\%" } );
            $html .= "<br>";
            $html .= $cgi->end_td;
            $html .= $cgi->start_td( { align => "left", width => "90\%" } );
            $html .= "<a href=\"#bwctl_service\">perfSONAR-BUOY (Iperf Data)</a>";
            $html .= $cgi->end_td;
            $html .= $cgi->end_Tr;
        }
        elsif ( $e eq "http://ggf.org/ns/nmwg/tools/pinger/2.0/" ) {
            $html .= $cgi->start_Tr;
            $html .= $cgi->start_td( { align => "left", width => "5\%" } );
            $html .= "<br>";
            $html .= $cgi->end_td;
            $html .= $cgi->start_td( { align => "left", width => "5\%" } );
            $html .= "<br>";
            $html .= $cgi->end_td;
            $html .= $cgi->start_td( { align => "left", width => "90\%" } );
            $html .= "<a href=\"#pinger_service\">PingER</a>";
            $html .= $cgi->end_td;
            $html .= $cgi->end_Tr;
        }
    }
    $html .= $cgi->end_table;
    $html .= $cgi->br;
    $html .= $cgi->br;
    $html .= $cgi->br;

    $html .= "<a name=\"daemons\" />";
    foreach my $e ( keys %etTotal ) {
        if (   $e eq "http://ggf.org/ns/nmwg/tools/ndt/1.0"
            or $e eq "http://ggf.org/ns/nmwg/tools/npad/1.0" )
        {

            if ( $e eq "http://ggf.org/ns/nmwg/tools/npad/1.0" ) {
                $html .= "<a name=\"npad_daemon\" />";
                $html .= $cgi->start_table( { border => "2", cellpadding => "1", align => "center", width => "85%" } );
                $html .= $cgi->start_Tr;
                $html .= $cgi->start_th( { colspan => "4", align => "center", width => "95\%" } );
                $html .= "NPAD Servers";
            }
            elsif ( $e eq "http://ggf.org/ns/nmwg/tools/ndt/1.0" ) {
                $html .= "<a name=\"ndt_daemon\" />";
                $html .= $cgi->start_table( { border => "2", cellpadding => "1", align => "center", width => "85%" } );
                $html .= $cgi->start_Tr;
                $html .= $cgi->start_th( { colspan => "4", align => "center", width => "95\%" } );
                $html .= "NDT Servers";
            }
            $html .= $cgi->end_th;
            $html .= $cgi->end_Tr;

            my @eventTypes = ();
            push @eventTypes, $e;
            my $result2 = $gls->getLSLocation( { eventTypes => \@eventTypes } );
            foreach my $service ( @{$result2} ) {
                my $doc2 = $parser->parse_string($service);

                my $address = extract( find( $doc2->getDocumentElement, ".//*[local-name()='address' and \@type=\"url\"]", 1 ), 0 );
                my $name    = extract( find( $doc2->getDocumentElement, ".//*[local-name()='name']",                       1 ), 0 );
                my $desc    = extract( find( $doc2->getDocumentElement, ".//*[local-name()='description']",                1 ), 0 );
                if ($address) {
                    $html .= $cgi->start_Tr;
                    $html .= $cgi->start_td( { colspan => "1", align => "left", width => "15\%" } );
                    if ($name) {
                        $html .= $name;
                    }
                    else {
                        $html .= "<br>";
                    }
                    $html .= $cgi->end_td;
                    $html .= $cgi->start_td( { colspan => "1", align => "center", width => "40\%" } );
                    $html .= "<a href=\"" . $address . "\">" . $address . "</a>";
                    $html .= $cgi->end_td;
                    $html .= $cgi->start_td( { colspan => "2", align => "left", width => "45\%" } );
                    if ($desc) {
                        $html .= $desc;
                    }
                    else {
                        $html .= "<br>";
                    }
                    $html .= $cgi->end_td;
                    $html .= $cgi->end_Tr;
                }
            }
            $html .= $cgi->end_table;
            $html .= $cgi->br;
            $html .= $cgi->br;
            $html .= $cgi->br;

        }
        elsif ($e eq "http://ggf.org/ns/nmwg/tools/owamp/1.0"
            or $e eq "http://ggf.org/ns/nmwg/tools/bwctl/1.0" )
        {

            if ( $e eq "http://ggf.org/ns/nmwg/tools/owamp/1.0" ) {
                $html .= "<a name=\"owamp_daemon\" />";
                $html .= $cgi->start_table( { border => "2", cellpadding => "1", align => "center", width => "85%" } );
                $html .= $cgi->start_Tr;
                $html .= $cgi->start_th( { colspan => "4", align => "center", width => "95\%" } );
                $html .= "OWAMP Servers";
            }
            elsif ( $e eq "http://ggf.org/ns/nmwg/tools/bwctl/1.0" ) {
                $html .= "<a name=\"bwctl_daemon\" />";
                $html .= $cgi->start_table( { border => "2", cellpadding => "1", align => "center", width => "85%" } );
                $html .= $cgi->start_Tr;
                $html .= $cgi->start_th( { colspan => "4", align => "center", width => "95\%" } );
                $html .= "BWCTL Servers";
            }
            $html .= $cgi->end_th;
            $html .= $cgi->end_Tr;

            my @eventTypes = ();
            push @eventTypes, $e;
            my $result2 = $gls->getLSLocation( { eventTypes => \@eventTypes } );
            foreach my $service ( @{$result2} ) {
                my $doc2 = $parser->parse_string($service);

                my $address = extract( find( $doc2->getDocumentElement, ".//*[local-name()='address' and \@type=\"uri\"]", 1 ), 0 );
                my $name    = extract( find( $doc2->getDocumentElement, ".//*[local-name()='name']",                       1 ), 0 );
                my $desc    = extract( find( $doc2->getDocumentElement, ".//*[local-name()='description']",                1 ), 0 );

                if ($address) {
                    $address =~ s/^tcp:\/\///;
                    $address =~ s/^udp:\/\///;
                    $html .= $cgi->start_Tr;
                    $html .= $cgi->start_td( { colspan => "1", align => "left", width => "15\%" } );
                    if ($name) {
                        $html .= $name;
                    }
                    else {
                        $html .= "<br>";
                    }
                    $html .= $cgi->end_td;
                    $html .= $cgi->start_td( { colspan => "1", align => "center", width => "40\%" } );
                    $html .= $address;
                    $html .= $cgi->end_td;
                    $html .= $cgi->start_td( { colspan => "2", align => "left", width => "45\%" } );
                    if ($desc) {
                        $html .= $desc;
                    }
                    else {
                        $html .= "<br>";
                    }
                    $html .= $cgi->end_td;
                    $html .= $cgi->end_Tr;
                }
            }
            $html .= $cgi->end_table;
            $html .= $cgi->br;
            $html .= $cgi->br;
            $html .= $cgi->br;

        }
    }

    $html .= "<a name=\"ps\" />";
    my $counter = 0;
    foreach my $e ( keys %etTotal ) {

        if ( $e eq "http://ggf.org/ns/nmwg/characteristic/utilization/2.0" ) {
            $html .= "<a name=\"utilization_service\" />";
            $html .= $cgi->start_table( { border => "2", cellpadding => "1", align => "center", width => "85%" } );
            $html .= $cgi->start_Tr;
            $html .= $cgi->start_th( { colspan => "4", align => "center", width => "95\%" } );
            $html .= "Utilization Data";
            $html .= $cgi->end_th;
            $html .= $cgi->end_Tr;

            my @eventTypes = ();
            push @eventTypes, $e;
            push @eventTypes, "http://ggf.org/ns/nmwg/tools/snmp/2.0";

            my $result2 = $gls->getLSLocation( { eventTypes => \@eventTypes } );
            foreach my $service ( @{$result2} ) {
                my $doc2 = $parser->parse_string($service);

                my $address = extract( find( $doc2->getDocumentElement, ".//*[local-name()='accessPoint']", 1 ), 0 );
                my $name    = extract( find( $doc2->getDocumentElement, ".//*[local-name()='serviceName']", 1 ), 0 );
                my $type    = extract( find( $doc2->getDocumentElement, ".//*[local-name()='serviceType']", 1 ), 0 );

                my $desc = extract( find( $doc2->getDocumentElement, ".//*[local-name()='serviceDescription']", 1 ), 0 );
                if ($address) {
                    $html .= $cgi->start_Tr;
                    $html .= $cgi->start_td( { colspan => "1", align => "left", width => "15\%" } );
                    if ($name) {
                        $html .= $name;
                    }
                    else {
                        $html .= "<br>";
                    }
                    $html .= $cgi->end_td;
                    $html .= $cgi->start_td( { colspan => "1", align => "left", width => "45\%" } );

                    #          $html .= "<a href=\"https://dc211.internet2.edu/cgi-bin/test.cgi?url=".$address."&eventType=http://ggf.org/ns/nmwg/characteristic/utilization/2.0\" />".$address."</a>";
                    $html .= $address;
                    $html .= $cgi->end_td;
                    $html .= $cgi->start_td( { colspan => "1", align => "left", width => "35\%" } );
                    if ($desc) {
                        $html .= $desc;
                    }
                    else {
                        $html .= "<br>";
                    }
                    $html .= $cgi->end_td;

                    $html .= $cgi->start_td( { colspan => "1", align => "center", width => "5\%" } );
                    $html .= "<input type=\"hidden\" name=\"url." . $counter . "\" ";
                    $html .= "id=\"url." . $counter . "\" value=\"" . $address . "\" />\n";
                    $html .= "<input type=\"hidden\" name=\"eT." . $counter . "\" ";
                    $html .= "id=\"eT." . $counter . "\" value=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0\" />\n";

                    $html .= "<input type=\"reset\" name=\"util_reset\" ";
                    $html .= "value=\"Reset\" onclick=\"reset( ";
                    $html .= "[], ['util_div." . $counter . "'] );\">\n";

                    $html .= "<input type=\"submit\" value=\"Contents\" id=\"util." . $counter . "\" ";
                    $html .= "name=\"util." . $counter . "\" onclick=\"draw_func( ";
                    $html .= "['url." . $counter . "', 'eT." . $counter . "'], ['util_div." . $counter . "'] );\"/>\n";
                    $html .= $cgi->end_td;
                    $html .= $cgi->end_Tr;
                    $html .= $cgi->start_Tr;
                    $html .= $cgi->start_td( { colspan => "4", align => "left", width => "100\%" } );
                    $html .= "<div id=\"util_div." . $counter . "\"></div>\n";
                    $html .= $cgi->end_td;
                    $html .= $cgi->end_Tr;
                    $counter++;

                }
            }
            $html .= $cgi->end_table;
            $html .= $cgi->br;
            $html .= $cgi->br;
            $html .= $cgi->br;
        }
        elsif ( $e eq "http://ggf.org/ns/nmwg/characteristic/delay/summary/20070921" ) {

            $html .= "<a name=\"owamp_service\" />";
            $html .= $cgi->start_table( { border => "2", cellpadding => "1", align => "center", width => "85%" } );
            $html .= $cgi->start_Tr;
            $html .= $cgi->start_th( { colspan => "4", align => "center", width => "95\%" } );
            $html .= "OWAMP Data Collection";
            $html .= $cgi->end_th;
            $html .= $cgi->end_Tr;

            my @eventTypes = ();
            push @eventTypes, $e;
            push @eventTypes, "http://ggf.org/ns/nmwg/tools/owamp/2.0";

            my $result2 = $gls->getLSLocation( { eventTypes => \@eventTypes } );
            foreach my $service ( @{$result2} ) {
                my $doc2 = $parser->parse_string($service);

                my $address = extract( find( $doc2->getDocumentElement, ".//*[local-name()='accessPoint']", 1 ), 0 );
                my $name    = extract( find( $doc2->getDocumentElement, ".//*[local-name()='serviceName']", 1 ), 0 );
                my $type    = extract( find( $doc2->getDocumentElement, ".//*[local-name()='serviceType']", 1 ), 0 );

                my $desc = extract( find( $doc2->getDocumentElement, ".//*[local-name()='serviceDescription']", 1 ), 0 );
                if ($address) {
                    $html .= $cgi->start_Tr;
                    $html .= $cgi->start_td( { colspan => "1", align => "left", width => "15\%" } );
                    if ($name) {
                        $html .= $name;
                    }
                    else {
                        $html .= "<br>";
                    }
                    $html .= $cgi->end_td;
                    $html .= $cgi->start_td( { colspan => "1", align => "left", width => "45\%" } );

                    #          $html .= "<a href=\"https://dc211.internet2.edu/cgi-bin/test.cgi?url=".$address."&eventType=http://ggf.org/ns/nmwg/characteristic/delay/summary/20070921\" />".$address."</a>";
                    $html .= $address;

                    $html .= $cgi->end_td;
                    $html .= $cgi->start_td( { colspan => "1", align => "left", width => "35\%" } );
                    if ($desc) {
                        $html .= $desc;
                    }
                    else {
                        $html .= "<br>";
                    }
                    $html .= $cgi->end_td;

                    $html .= $cgi->start_td( { colspan => "1", align => "center", width => "5\%" } );
                    $html .= "<input type=\"hidden\" name=\"url." . $counter . "\" ";
                    $html .= "id=\"url." . $counter . "\" value=\"" . $address . "\" />\n";
                    $html .= "<input type=\"hidden\" name=\"eT." . $counter . "\" ";
                    $html .= "id=\"eT." . $counter . "\" value=\"http://ggf.org/ns/nmwg/tools/owamp/2.0\" />\n";

                    $html .= "<input type=\"reset\" name=\"owamp_reset\" ";
                    $html .= "value=\"Reset\" onclick=\"reset( ";
                    $html .= "[], ['owamp_div." . $counter . "'] );\">\n";

                    $html .= "<input type=\"submit\" value=\"Contents\" id=\"owamp." . $counter . "\" ";
                    $html .= "name=\"owamp." . $counter . "\" onclick=\"draw_func( ";
                    $html .= "['url." . $counter . "', 'eT." . $counter . "'], ['owamp_div." . $counter . "'] );\"/>\n";
                    $html .= $cgi->end_td;
                    $html .= $cgi->end_Tr;
                    $html .= $cgi->start_Tr;
                    $html .= $cgi->start_td( { colspan => "4", align => "left", width => "100\%" } );
                    $html .= "<div id=\"owamp_div." . $counter . "\"></div>\n";
                    $html .= $cgi->end_td;
                    $html .= $cgi->end_Tr;
                    $counter++;

                }
            }
            $html .= $cgi->end_table;
            $html .= $cgi->br;
            $html .= $cgi->br;
            $html .= $cgi->br;
        }
        elsif ( $e eq "http://ggf.org/ns/nmwg/characteristics/bandwidth/acheiveable/2.0" ) {

            $html .= "<a name=\"bwctl_service\" />";
            $html .= $cgi->start_table( { border => "2", cellpadding => "1", align => "center", width => "85%" } );
            $html .= $cgi->start_Tr;
            $html .= $cgi->start_th( { colspan => "4", align => "center", width => "95\%" } );
            $html .= "BWCTL Data Collection";
            $html .= $cgi->end_th;
            $html .= $cgi->end_Tr;

            my @eventTypes = ();
            push @eventTypes, $e;
            push @eventTypes, "http://ggf.org/ns/nmwg/tools/iperf/2.0";

            my $result2 = $gls->getLSLocation( { eventTypes => \@eventTypes } );
            foreach my $service ( @{$result2} ) {
                my $doc2 = $parser->parse_string($service);

                my $address = extract( find( $doc2->getDocumentElement, ".//*[local-name()='accessPoint']", 1 ), 0 );
                my $name    = extract( find( $doc2->getDocumentElement, ".//*[local-name()='serviceName']", 1 ), 0 );
                my $type    = extract( find( $doc2->getDocumentElement, ".//*[local-name()='serviceType']", 1 ), 0 );

                my $desc = extract( find( $doc2->getDocumentElement, ".//*[local-name()='serviceDescription']", 1 ), 0 );
                if ($address) {
                    $html .= $cgi->start_Tr;
                    $html .= $cgi->start_td( { colspan => "1", align => "left", width => "15\%" } );
                    if ($name) {
                        $html .= $name;
                    }
                    else {
                        $html .= "<br>";
                    }
                    $html .= $cgi->end_td;
                    $html .= $cgi->start_td( { colspan => "1", align => "left", width => "45\%" } );

                    $html .= $address;

                    #          $html .= "<a href=\"https://dc211.internet2.edu/cgi-bin/test.cgi?url=".$address."&eventType=http://ggf.org/ns/nmwg/tools/iperf/2.0\" />".$address."</a>";

                    $html .= $cgi->end_td;
                    $html .= $cgi->start_td( { colspan => "1", align => "left", width => "35\%" } );
                    if ($desc) {
                        $html .= $desc;
                    }
                    else {
                        $html .= "<br>";
                    }
                    $html .= $cgi->end_td;

                    $html .= $cgi->start_td( { colspan => "1", align => "center", width => "5\%" } );
                    $html .= "<input type=\"hidden\" name=\"url." . $counter . "\" ";
                    $html .= "id=\"url." . $counter . "\" value=\"" . $address . "\" />\n";
                    $html .= "<input type=\"hidden\" name=\"eT." . $counter . "\" ";
                    $html .= "id=\"eT." . $counter . "\" value=\"http://ggf.org/ns/nmwg/tools/iperf/2.0\" />\n";

                    $html .= "<input type=\"reset\" name=\"bwctl_reset\" ";
                    $html .= "value=\"Reset\" onclick=\"reset( ";
                    $html .= "[], ['bwctl_div." . $counter . "'] );\">\n";

                    $html .= "<input type=\"submit\" value=\"Contents\" id=\"bwctl." . $counter . "\" ";
                    $html .= "name=\"bwctl." . $counter . "\" onclick=\"draw_func( ";
                    $html .= "['url." . $counter . "', 'eT." . $counter . "'], ['bwctl_div." . $counter . "'] );\"/>\n";
                    $html .= $cgi->end_td;
                    $html .= $cgi->end_Tr;
                    $html .= $cgi->start_Tr;
                    $html .= $cgi->start_td( { colspan => "4", align => "left", width => "100\%" } );
                    $html .= "<div id=\"bwctl_div." . $counter . "\"></div>\n";
                    $html .= $cgi->end_td;
                    $html .= $cgi->end_Tr;
                    $counter++;

                }
            }
            $html .= $cgi->end_table;
            $html .= $cgi->br;
            $html .= $cgi->br;
            $html .= $cgi->br;
        }
        elsif ( $e eq "http://ggf.org/ns/nmwg/tools/pinger/2.0/" ) {

            $html .= "<a name=\"pinger_service\" />";
            $html .= $cgi->start_table( { border => "2", cellpadding => "1", align => "center", width => "85%" } );
            $html .= $cgi->start_Tr;
            $html .= $cgi->start_th( { colspan => "4", align => "center", width => "95\%" } );
            $html .= "PingER";
            $html .= $cgi->end_th;
            $html .= $cgi->end_Tr;

            my @eventTypes = ();
            push @eventTypes, $e;

            my $result2 = $gls->getLSLocation( { eventTypes => \@eventTypes } );
            foreach my $service ( @{$result2} ) {
                my $doc2 = $parser->parse_string($service);

                my $address = extract( find( $doc2->getDocumentElement, ".//*[local-name()='accessPoint']", 1 ), 0 );
                my $name    = extract( find( $doc2->getDocumentElement, ".//*[local-name()='serviceName']", 1 ), 0 );
                my $type    = extract( find( $doc2->getDocumentElement, ".//*[local-name()='serviceType']", 1 ), 0 );

                my $desc = extract( find( $doc2->getDocumentElement, ".//*[local-name()='serviceDescription']", 1 ), 0 );
                if ($address) {
                    $html .= $cgi->start_Tr;
                    $html .= $cgi->start_td( { colspan => "1", align => "left", width => "15\%" } );
                    if ($name) {
                        $html .= $name;
                    }
                    else {
                        $html .= "<br>";
                    }
                    $html .= $cgi->end_td;

                    $html .= $cgi->start_td( { colspan => "1", align => "left", width => "45\%" } );
                    $html .= $address;
                    $html .= $cgi->end_td;

                    $html .= $cgi->start_td( { colspan => "1", align => "left", width => "35\%" } );
                    if ($desc) {
                        $html .= $desc;
                    }
                    else {
                        $html .= "<br>";
                    }
                    $html .= $cgi->end_td;

                    $html .= $cgi->start_td( { colspan => "1", align => "center", width => "5\%" } );
                    $html .= "<input type=\"hidden\" name=\"url." . $counter . "\" ";
                    $html .= "id=\"url." . $counter . "\" value=\"" . $address . "\" />\n";
                    $html .= "<input type=\"hidden\" name=\"eT." . $counter . "\" ";
                    $html .= "id=\"eT." . $counter . "\" value=\"http://ggf.org/ns/nmwg/tools/pinger/2.0/\" />\n";

                    $html .= "<input type=\"reset\" name=\"pinger_reset\" ";
                    $html .= "value=\"Reset\" onclick=\"reset( ";
                    $html .= "[], ['pinger_div." . $counter . "'] );\">\n";

                    $html .= "<input type=\"submit\" value=\"Contents\" id=\"pinger." . $counter . "\" ";
                    $html .= "name=\"pinger." . $counter . "\" onclick=\"draw_func( ";
                    $html .= "['url." . $counter . "', 'eT." . $counter . "'], ['pinger_div." . $counter . "'] );\"/>\n";
                    $html .= $cgi->end_td;
                    $html .= $cgi->end_Tr;
                    $html .= $cgi->start_Tr;
                    $html .= $cgi->start_td( { colspan => "4", align => "left", width => "100\%" } );
                    $html .= "<div id=\"pinger_div." . $counter . "\"></div>\n";
                    $html .= $cgi->end_td;
                    $html .= $cgi->end_Tr;
                    $counter++;

                }
            }
            $html .= $cgi->end_table;
            $html .= $cgi->br;
            $html .= $cgi->br;
            $html .= $cgi->br;
        }
    }
    $html .= $cgi->br;

    $html .= $cgi->end_html;
    return $html;
}


__END__

=head1 SEE ALSO

L<XML::LibXML>, L<Date::Manip>, L<CGI>, L<CGI::Ajax>, L<Socket>, L<POSIX>,
L<IO::Socket>, L<IO::Socket::INET>, L<IO::Interface>

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

