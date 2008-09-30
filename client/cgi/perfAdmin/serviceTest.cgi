#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

serviceTest.cgi - Test out a perfSONAR service (usually a MA) by doing a simple
query and attempting the visualize data (where applicable).

=head1 DESCRIPTION

Perform a metadata key request on a service and offer the ability to graph (if
available for the data type).  

=cut

use XML::LibXML;
use CGI;
use CGI::Ajax;
use CGI::Carp qw( fatalsToBrowser );

use Socket;
use POSIX;
use IO::Socket;
use IO::Socket::INET;
use IO::Interface qw(:flags);

use lib "/usr/local/perfSONAR-PS/lib";

use perfSONAR_PS::Client::MA;
use perfSONAR_PS::Common qw( extract find );

my $cgi = new CGI;
my $pjx = new CGI::Ajax( 'draw_func' => \&drawGauge );

my $service;
if ( $cgi->param('url') ) {
    $service = $cgi->param('url');
}
else {
    die "Service URL not provided.\n";
}

my $eventType;
if ( $cgi->param('eventType') ) {
    $eventType = $cgi->param('eventType');
    $eventType =~ s/(\s|\n)*//g;
}
else {
    die "Service eventType not provided.\n";
}

my $ma = new perfSONAR_PS::Client::MA( { instance => $service } );

print $pjx->build_html( $cgi, \&display );

sub drawGauge {
    my ( $load, $key_in, $key_out ) = @_;

    my $html = q{};
    if ( defined $load and $load ) {

        #    $html .= $key_in."<br>".$key_out."<br>\n";
    }
    return $html;
}

sub display {

    my $html = $cgi->start_html( -title => 'MA Output' );

    $html .= $cgi->br;
    $html .= $cgi->br;

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
        $html .= $cgi->br;
        $html .= $cgi->end_html;
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
        $html .= "<center><h2>MA <b><i>" . $service . "</i></b> experienced an error, is it functioning?</h2></center>\n";
        $html .= $cgi->br;
        $html .= $cgi->br;
        $html .= $cgi->end_html;
        return $html;
    }

    my $metadata = $parser->parse_string( $result->{"metadata"}->[0] );
    my $et = extract( find( $metadata->getDocumentElement, ".//nmwg:eventType", 1 ), 0 );

    if ( $et eq "error.ma.storage" ) {
        $html .= "<center><h2>MA <b><i>" . $service . "</i></b> experienced an error, be sure it is configured and populated with data.</h2></center>\n";
        $html .= $cgi->br;
        $html .= $cgi->br;
        $html .= $cgi->end_html;
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

            $html .= $cgi->start_table( { border => "2", cellpadding => "1", align => "center", width => "95%" } );

            $html .= $cgi->start_Tr;
            $html .= $cgi->start_th( { colspan => "8", align => "center" } );
            $html .= $eventType . " @ " . $service;
            $html .= $cgi->end_th;
            $html .= $cgi->end_Tr;

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
                    $html .= $cgi->start_Tr;
                    $html .= $cgi->start_td( { colspan => 9, align => "center" } );
                    $html .= "<div id=\"resultdiv." . $counter . "\"></div>\n";
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

            $html .= $cgi->start_table( { border => "2", cellpadding => "1", align => "center", width => "95%" } );

            $html .= $cgi->start_Tr;
            $html .= $cgi->start_th( { colspan => "7", align => "center" } );
            $html .= $eventType . " @ " . $service;
            $html .= $cgi->end_th;
            $html .= $cgi->end_Tr;

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

                        $html .= $cgi->start_td( { align => "center" } );
                        $html .= $list{$src}{$dst}{$type}->{"src"}, "\n";
                        $html .= $cgi->end_td;

                        my $display = $list{$src}{$dst}{$type}->{"src"};
                        $display =~ s/:.*$//;
                        my $iaddr = Socket::inet_aton($display);
                        my $shost = gethostbyaddr( $iaddr, Socket::AF_INET );
                        $html .= $cgi->start_td( { align => "center" } );
                        if ($shost) {
                            $html .= $shost . "\n";
                        }
                        else {
                            $html .= $list{$src}{$dst}{$type}->{"src"}, "\n";
                        }
                        $html .= $cgi->end_td;

                        $html .= $cgi->start_td( { align => "center" } );
                        $html .= $list{$src}{$dst}{$type}->{"dst"}, "\n";
                        $html .= $cgi->end_td;

                        my $display2 = $list{$src}{$dst}{$type}->{"dst"};
                        $display2 =~ s/:.*$//;
                        my $iaddr = Socket::inet_aton($display2);
                        my $dhost = gethostbyaddr( $iaddr, Socket::AF_INET );
                        $html .= $cgi->start_td( { align => "center" } );
                        if ($dhost) {
                            $html .= $dhost . "\n";
                        }
                        else {
                            $html .= $list{$src}{$dst}{$type}->{"dst"}, "\n";
                        }
                        $html .= $cgi->end_td;

                        $html .= $cgi->start_td( { align => "center" } );
                        $html .= $list{$src}{$dst}{$type}->{"type"}, "\n";
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
                        $html .= $cgi->start_Tr;
                        $html .= $cgi->start_td( { colspan => 7, align => "center" } );
                        $html .= "<div id=\"resultdiv." . $counter . "\"></div>\n";
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

            $html .= $cgi->start_table( { border => "2", cellpadding => "1", align => "center", width => "95%" } );

            $html .= $cgi->start_Tr;
            $html .= $cgi->start_th( { colspan => "5", align => "center" } );
            $html .= $eventType . " @ " . $service;
            $html .= $cgi->end_th;
            $html .= $cgi->end_Tr;

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

                    my $display2 = $list{$src}{$dst}->{"dst"};
                    $display2 =~ s/:.*$//;
                    my $iaddr = Socket::inet_aton($display2);
                    my $dhost = gethostbyaddr( $iaddr, Socket::AF_INET );
                    $html .= $cgi->start_td( { align => "center" } );
                    if ($dhost) {
                        $html .= $dhost . "\n";
                    }
                    else {
                        $html .= $list{$src}{$dst}->{"dst"}, "\n";
                    }
                    $html .= $cgi->end_td;

                    $html .= $cgi->start_td( { align => "center" } );
                    $html .= $list{$src}{$dst}->{"dst"}, "\n";
                    $html .= $cgi->end_td;

                    $html .= $cgi->start_td( { align => "center" } );
                    $html .= "<input type=\"submit\" value=\"Graph\" id=\"if." . $counter . "\" ";
                    $html .= "name=\"if." . $counter . "\" onClick=\"window.open(";
                    $html .= "'delayGraph.cgi?url=" . $service . "&key=" . $list{$src}{$dst}->{"key"} . "','graphwindow." . $counter . "','width=950,";
                    $html .= "height=450,status=yes,scrollbars=yes,resizable=yes')\" />\n";
                    $html .= $cgi->end_td;
                    $html .= $cgi->end_Tr;
                    $html .= $cgi->start_Tr;
                    $html .= $cgi->start_td( { colspan => 8, align => "center" } );
                    $html .= "<div id=\"resultdiv." . $counter . "\"></div>\n";
                    $html .= $cgi->end_td;
                    $html .= $cgi->end_Tr;

                    $counter++;
                }
            }
        }
        elsif ( $eventType eq "http://ggf.org/ns/nmwg/tools/pinger/2.0/" ) {

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
            $html .= $cgi->start_th( { colspan => "5", align => "center" } );
            $html .= $eventType . " @ " . $service;
            $html .= $cgi->end_th;
            $html .= $cgi->end_Tr;

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
            $html .= $cgi->br;
            $html .= $cgi->end_html;
            return $html;
        }
    }

    $html .= $cgi->br;

    $html .= $cgi->end_html;
    return $html;
}


__END__

=head1 SEE ALSO

L<XML::LibXML>, L<CGI>, L<CGI::Ajax>, L<CGI::Carp>, L<Socket>, L<POSIX>,
L<IO::Socket>, L<IO::Socket::INET>, L<IO::Interface>,
L<perfSONAR_PS::Client::MA>, L<perfSONAR_PS::Common>

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

