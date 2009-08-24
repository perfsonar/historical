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

use CGI;
use HTML::Template;
use XML::LibXML;
use Socket;
use Data::Validate::IP qw(is_ipv4);
use Net::IPv6Addr;
use English qw( -no_match_vars );

use FindBin qw($RealBin);
my $basedir = "$RealBin/";
use lib "$RealBin/../lib";

use perfSONAR_PS::Client::MA;
use perfSONAR_PS::Common qw( extract find );
use perfSONAR_PS::Utils::ParameterValidation;

my $template = q{};
my $cgi      = CGI->new();
print $cgi->header();

my $service;
if ( $cgi->param( 'url' ) ) {
    $service = $cgi->param( 'url' );
}
else {
    $template = HTML::Template->new( filename => "$RealBin/../etc/serviceTest_error.tmpl" );
    $template->param( ERROR => "Service URL not provided." );
    print $template->output;
    exit( 1 );
}

my $eventType;
if ( $cgi->param( 'eventType' ) ) {
    $eventType = $cgi->param( 'eventType' );
    $eventType =~ s/(\s|\n)*//g;
}
else {
    $template = HTML::Template->new( filename => "$RealBin/../etc/serviceTest_error.tmpl" );
    $template->param( ERROR => "Service eventType not provided." );
    print $template->output;
    exit( 1 );
}

my $ma = new perfSONAR_PS::Client::MA( { instance => $service } );

my $subject;
my @eventTypes = ();
push @eventTypes, $eventType;
if ( $eventType eq "http://ggf.org/ns/nmwg/characteristic/utilization/2.0" ) {
    $subject = "    <netutil:subject xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\" id=\"s\">\n";
    $subject .= "      <nmwgt:interface xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\" />\n";
    $subject .= "    </netutil:subject>\n";
}
elsif ($eventType eq "http://ggf.org/ns/nmwg/tools/iperf/2.0"
    or $eventType eq "http://ggf.org/ns/nmwg/characteristics/bandwidth/acheiveable/2.0"
    or $eventType eq "http://ggf.org/ns/nmwg/characteristics/bandwidth/achieveable/2.0"
    or $eventType eq "http://ggf.org/ns/nmwg/characteristics/bandwidth/achievable/2.0" )
{
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
    $template = HTML::Template->new( filename => "$RealBin/../etc/serviceTest_error.tmpl" );
    $template->param( ERROR => "Unrecognized eventType: \"" . $eventType . "\"." );
    print $template->output;
    exit( 1 );
}

my $parser = XML::LibXML->new();
my $result = $ma->metadataKeyRequest(
    {
        subject    => $subject,
        eventTypes => \@eventTypes
    }
);

unless ( $#{ $result->{"metadata"} } > -1 ) {
    $template = HTML::Template->new( filename => "$RealBin/../etc/serviceTest_error.tmpl" );
    $template->param( ERROR => "MA <b><i>" . $service . "</i></b> experienced an error, is it functioning?" );
    print $template->output;
    exit( 1 );
}

my $metadata = q{};
eval { $metadata = $parser->parse_string( $result->{"metadata"}->[0] ); };
if ( $EVAL_ERROR ) {
    $template = HTML::Template->new( filename => "$RealBin/../etc/serviceTest_error.tmpl" );
    $template->param( ERROR => "Could not parse XML response from MA <b><i>" . $service . "</i></b>." );
    print $template->output;
    exit( 1 );
}

my $et = extract( find( $metadata->getDocumentElement, ".//nmwg:eventType", 1 ), 0 );

if ( $et eq "error.ma.storage" ) {
    $template = HTML::Template->new( filename => "$RealBin/../etc/serviceTest_error.tmpl" );
    $template->param( ERROR => "MA <b><i>" . $service . "</i></b> experienced an error, be sure it is configured and populated with data." );
}
else {
    if ( $eventType eq "http://ggf.org/ns/nmwg/characteristic/utilization/2.0" ) {
        $template = HTML::Template->new( filename => "$RealBin/../etc/serviceTest_utilization.tmpl" );

        my %lookup = ();
        foreach my $d ( @{ $result->{"data"} } ) {
            my $data = q{};
            eval { $data = $parser->parse_string( $d ); };
            if ( $EVAL_ERROR ) {
                $template = HTML::Template->new( filename => "$RealBin/../etc/serviceTest_error.tmpl" );
                $template->param( ERROR => "Could not parse XML response from MA <b><i>" . $service . "</i></b>." );
                print $template->output;
                exit( 1 );
            }

            my $metadataIdRef = $data->getDocumentElement->getAttribute( "metadataIdRef" );
            my $key           = extract( find( $data->getDocumentElement, ".//nmwg:parameter[\@name=\"maKey\"]", 1 ), 0 );
            if ( $key ) {
                $lookup{$metadataIdRef}{"key1"} = $key if $metadataIdRef;
                $lookup{$metadataIdRef}{"key2"} = q{};
                $lookup{$metadataIdRef}{"type"} = "key";
            }
            else {
                $key = extract( find( $data->getDocumentElement, ".//nmwg:parameter[\@name=\"file\"]", 1 ), 0 );
                $lookup{$metadataIdRef}{"key1"} = $key if $key and $metadataIdRef;
                $key = extract( find( $data->getDocumentElement, ".//nmwg:parameter[\@name=\"dataSource\"]", 1 ), 0 );
                $lookup{$metadataIdRef}{"key2"} = $key if $key and $metadataIdRef;
                $lookup{$metadataIdRef}{"type"} = "nonkey";
            }
        }

        my %list = ();
        foreach my $md ( @{ $result->{"metadata"} } ) {
            my $metadata = q{};
            eval { $metadata = $parser->parse_string( $md ); };
            if ( $EVAL_ERROR ) {
                $template = HTML::Template->new( filename => "$RealBin/../etc/serviceTest_error.tmpl" );
                $template->param( ERROR => "Could not parse XML response from MA <b><i>" . $service . "</i></b>." );
                print $template->output;
                exit( 1 );
            }

            my $metadataId = $metadata->getDocumentElement->getAttribute( "id" );
            my $dir        = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:interface/nmwgt:direction", 1 ), 0 );
            my $host       = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:interface/nmwgt:hostName", 1 ), 0 );
            my $name       = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:interface/nmwgt:ifName", 1 ), 0 );
            if ( $list{$host}{$name} ) {
                if ( $dir eq "in" ) {
                    $list{$host}{$name}->{"key1_1"}    = $lookup{$metadataId}{"key1"};
                    $list{$host}{$name}->{"key1_2"}    = $lookup{$metadataId}{"key2"};
                    $list{$host}{$name}->{"key1_type"} = $lookup{$metadataId}{"type"};
                }
                else {
                    $list{$host}{$name}->{"key2_1"}    = $lookup{$metadataId}{"key1"};
                    $list{$host}{$name}->{"key2_2"}    = $lookup{$metadataId}{"key2"};
                    $list{$host}{$name}->{"key2_type"} = $lookup{$metadataId}{"type"};
                }
            }
            else {
                my %temp = ();
                if ( $dir eq "in" ) {
                    $temp{"key1_1"}    = $lookup{$metadataId}{"key1"};
                    $temp{"key1_2"}    = $lookup{$metadataId}{"key2"};
                    $temp{"key1_type"} = $lookup{$metadataId}{"type"};
                }
                else {
                    $temp{"key2_1"}    = $lookup{$metadataId}{"key1"};
                    $temp{"key2_2"}    = $lookup{$metadataId}{"key2"};
                    $temp{"key2_type"} = $lookup{$metadataId}{"type"};
                }
                $temp{"hostName"}      = $host;
                $temp{"ifName"}        = $name;
                $temp{"ifIndex"}       = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:interface/nmwgt:ifIndex", 1 ), 0 );
                $temp{"ipAddress"}     = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:interface/nmwgt:ipAddress", 1 ), 0 );
                $temp{"ifDescription"} = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:interface/nmwgt:ifDescription", 1 ), 0 );
                unless ( exists $temp{"ifDescription"} and $temp{"ifDescription"} ) {
                    $temp{"ifDescription"} = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:interface/nmwgt:description", 1 ), 0 );
                }
                $temp{"ifAddress"} = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:interface/nmwgt:ifAddress", 1 ), 0 );
                $temp{"capacity"}  = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:interface/nmwgt:capacity",  1 ), 0 );

                if ( $temp{"capacity"} ) {
                    $temp{"capacity"} /= 1000000;
                    if ( $temp{"capacity"} < 1000 ) {
                        $temp{"capacity"} .= " Mbps";
                    }
                    elsif ( $temp{"capacity"} < 1000000 ) {
                        $temp{"capacity"} /= 1000;
                        $temp{"capacity"} .= " Gbps";
                    }
                    elsif ( $temp{"capacity"} < 1000000000 ) {
                        $temp{"capacity"} /= 1000000;
                        $temp{"capacity"} .= " Tbps";
                    }
                }
                $list{$host}{$name} = \%temp;
            }
        }

        my @interfaces = ();
        my $counter    = 0;
        foreach my $host ( sort keys %list ) {
            foreach my $name ( sort keys %{ $list{$host} } ) {

                push @interfaces,
                    {
                    ADDRESS   => $list{$host}{$name}->{"ipAddress"},
                    HOST      => $list{$host}{$name}->{"hostName"},
                    IFNAME    => $list{$host}{$name}->{"ifName"},
                    IFINDEX   => $list{$host}{$name}->{"ifIndex"},
                    DESC      => $list{$host}{$name}->{"ifDescription"},
                    IFADDRESS => $list{$host}{$name}->{"ifAddress"},
                    CAPACITY  => $list{$host}{$name}->{"capacity"},
                    KEY1TYPE  => $list{$host}{$name}->{"key1_type"},
                    KEY11     => $list{$host}{$name}->{"key1_1"},
                    KEY12     => $list{$host}{$name}->{"key1_2"},
                    KEY2TYPE  => $list{$host}{$name}->{"key2_type"},
                    KEY21     => $list{$host}{$name}->{"key2_1"},
                    KEY22     => $list{$host}{$name}->{"key2_2"},
                    COUNT     => $counter,
                    SERVICE   => $service
                    };

                $counter++;
            }
        }

        $template->param(
            EVENTTYPE  => $eventType,
            SERVICE    => $service,
            INTERFACES => \@interfaces
        );

    }
    elsif ($eventType eq "http://ggf.org/ns/nmwg/tools/iperf/2.0"
        or $eventType eq "http://ggf.org/ns/nmwg/characteristics/bandwidth/acheiveable/2.0"
        or $eventType eq "http://ggf.org/ns/nmwg/characteristics/bandwidth/achieveable/2.0"
        or $eventType eq "http://ggf.org/ns/nmwg/characteristics/bandwidth/achievable/2.0" )
    {
        my $sec = time;
        $template = HTML::Template->new( filename => "$RealBin/../etc/serviceTest_psb_bwctl.tmpl" );

        my %lookup = ();
        foreach my $d ( @{ $result->{"data"} } ) {
            my $data = q{};
            eval { $data = $parser->parse_string( $d ); };
            if ( $EVAL_ERROR ) {
                $template = HTML::Template->new( filename => "$RealBin/../etc/serviceTest_error.tmpl" );
                $template->param( ERROR => "Could not parse XML response from MA <b><i>" . $service . "</i></b>." );
                print $template->output;
                exit( 1 );
            }

            my $metadataIdRef = $data->getDocumentElement->getAttribute( "metadataIdRef" );
            my $key           = extract( find( $data->getDocumentElement, ".//nmwg:parameter[\@name=\"maKey\"]", 1 ), 0 );
            $lookup{$metadataIdRef} = $key if $key and $metadataIdRef;
        }

        my %list = ();
        my %data = ();
        foreach my $md ( @{ $result->{"metadata"} } ) {
            my $metadata = q{};
            eval { $metadata = $parser->parse_string( $md ); };
            if ( $EVAL_ERROR ) {
                $template = HTML::Template->new( filename => "$RealBin/../etc/serviceTest_error.tmpl" );
                $template->param( ERROR => "Could not parse XML response from MA <b><i>" . $service . "</i></b>." );
                print $template->output;
                exit( 1 );
            }

            my $metadataId = $metadata->getDocumentElement->getAttribute( "id" );

            my $src   = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:endPointPair/nmwgt:src", 1 ), 0 );
            my $saddr = q{};
            my $shost = q{};
            if ( is_ipv4( $src ) ) {
                $saddr = $src;
                my $iaddr = Socket::inet_aton( $src );
                if ( defined $iaddr and $iaddr ) {
                    $shost = gethostbyaddr( $iaddr, Socket::AF_INET );
                }
                $shost = $src unless $shost;
            }
            elsif ( &Net::IPv6Addr::is_ipv6( $src ) ) {
                $saddr = $src;
                $shost = $src;

                # do something?
            }
            else {
                $shost = $src;
                my $packed_ip = gethostbyname( $src );
                if ( defined $packed_ip and $packed_ip ) {
                    $saddr = inet_ntoa( $packed_ip );
                }
                $saddr = $src unless $saddr;
            }

            my $dst   = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:endPointPair/nmwgt:dst", 1 ), 0 );
            my $daddr = q{};
            my $dhost = q{};
            if ( is_ipv4( $dst ) ) {
                $daddr = $dst;
                my $iaddr = Socket::inet_aton( $dst );
                if ( defined $iaddr and $iaddr ) {
                    $dhost = gethostbyaddr( $iaddr, Socket::AF_INET );
                }
                $dhost = $dst unless $dhost;
            }
            elsif ( &Net::IPv6Addr::is_ipv6( $dst ) ) {
                $daddr = $dst;
                $dhost = $dst;

                # do something?
            }
            else {
                $dhost = $dst;
                my $packed_ip = gethostbyname( $dst );
                if ( defined $packed_ip and $packed_ip ) {
                    $daddr = inet_ntoa( $packed_ip );
                }
                $daddr = $dst unless $daddr;
            }

            my %temp = ();
            my $params = find( $metadata->getDocumentElement, "./*[local-name()='parameters']/*[local-name()='parameter']", 0 );
            foreach my $p ( $params->get_nodelist ) {
                my $pName = $p->getAttribute( "name" );
                my $pValue = extract( $p, 0 );
                $temp{$pName} = $pValue if $pName and $pValue;
            }

            $temp{"key"}   = $lookup{$metadataId};
            $temp{"src"}   = $shost;
            $temp{"dst"}   = $dhost;
            $temp{"saddr"} = $saddr;
            $temp{"daddr"} = $daddr;

            unless ( exists $data{$shost} ) {
                $data{$shost}{"out"}{"total"} = 0;
                $data{$shost}{"in"}{"total"}  = 0;
                $data{$shost}{"out"}{"count"} = 0;
                $data{$shost}{"in"}{"count"}  = 0;
            }
            unless ( exists $data{$dhost} ) {
                $data{$dhost}{"out"}{"total"} = 0;
                $data{$dhost}{"in"}{"total"}  = 0;
                $data{$dhost}{"out"}{"count"} = 0;
                $data{$dhost}{"in"}{"count"}  = 0;
            }

            my @eventTypes = ();
            my $parser     = XML::LibXML->new();

            my $subject = "<nmwg:key id=\"key-1\"><nmwg:parameters id=\"parameters-key-1\"><nmwg:parameter name=\"maKey\">" . $lookup{$metadataId} . "</nmwg:parameter></nmwg:parameters></nmwg:key>";
            my $time    = 604800;

            my $result = $ma->setupDataRequest(
                {
                    start      => ( $sec - $time ),
                    end        => $sec,
                    subject    => $subject,
                    eventTypes => \@eventTypes
                }
            );

            my $doc1 = q{};
            eval { $doc1 = $parser->parse_string( $result->{"data"}->[0] ); };
            if ( $EVAL_ERROR ) {
                $template = HTML::Template->new( filename => "$RealBin/../etc/serviceTest_error.tmpl" );
                $template->param( ERROR => "Could not parse XML response from MA <b><i>" . $service . "</i></b>." );
                print $template->output;
                exit( 1 );
            }

            my $datum1 = find( $doc1->getDocumentElement, "./*[local-name()='datum']", 0 );
            if ( $datum1 ) {
                my $dcounter = 0;
                my $total    = 0;
                foreach my $dt ( $datum1->get_nodelist ) {
                    if ( $dt->getAttribute( "throughput" ) ) {
                        $total += $dt->getAttribute( "throughput" );
                        $dcounter++;
                    }
                }

                if ( $dcounter ) {
                    $data{$shost}{"out"}{"total"} += ( $total / $dcounter ) if $dcounter;
                    $data{$dhost}{"in"}{"total"}  += ( $total / $dcounter ) if $dcounter;
                    $data{$shost}{"out"}{"count"}++;
                    $data{$dhost}{"in"}{"count"}++;
                    $temp{"active"} = 1;
                    $temp{"out"} = ( $total / $dcounter ) if $dcounter;
                }
                else {
                    $temp{"active"} = 0;
                }
            }
            else {
                $temp{"active"} = 0;
            }
            push @{ $list{$shost}{$dhost} }, \%temp;
        }

        # figure out if hosts are equal - requires unrolling all of the options and comparing (ugh)
        my %hostMap = ();
        foreach my $src ( sort keys %list ) {
            foreach my $dst ( sort keys %{ $list{$src} } ) {
                foreach my $set ( @{ $list{$src}{$dst} } ) {
                    if ( $#{ $list{$src}{$dst} } > -1 and $#{ $list{$dst}{$src} } > -1 ) {
                        foreach my $set2 ( @{ $list{$dst}{$src} } ) {
                            if ( $set->{"src"} eq $set2->{"dst"} and $set->{"dst"} eq $set2->{"src"} and $set->{"saddr"} eq $set2->{"daddr"} and $set->{"daddr"} eq $set2->{"saddr"} ) {
                                my @type = ( q{}, q{} );
                                $type[0] = $set->{"type"}  if $set->{"type"};
                                $type[1] = $set2->{"type"} if $set2->{"type"};
                                next unless $type[0] eq $type[1];

                                my @timeDuration = ( q{}, q{} );
                                $timeDuration[0] = $set->{"timeDuration"}  if $set->{"timeDuration"};
                                $timeDuration[1] = $set2->{"timeDuration"} if $set2->{"timeDuration"};
                                next unless $timeDuration[0] eq $timeDuration[1];

                                my @windowSize = ( q{}, q{} );
                                $windowSize[0] = $set->{"windowSize"}  if $set->{"windowSize"};
                                $windowSize[1] = $set2->{"windowSize"} if $set2->{"windowSize"};
                                next unless $windowSize[0] eq $windowSize[1];

                                my @bufferLength = ( q{}, q{} );
                                $bufferLength[0] = $set->{"bufferLength"}  if $set->{"bufferLength"};
                                $bufferLength[1] = $set2->{"bufferLength"} if $set2->{"bufferLength"};
                                next unless $bufferLength[0] eq $bufferLength[1];

                                my @interval = ( q{}, q{} );
                                $interval[0] = $set->{"interval"}  if $set->{"interval"};
                                $interval[1] = $set2->{"interval"} if $set2->{"interval"};
                                next unless $interval[0] eq $interval[1];

                                my @bandwidthLimit = ( q{}, q{} );
                                $bandwidthLimit[0] = $set->{"bandwidthLimit"}  if $set->{"bandwidthLimit"};
                                $bandwidthLimit[1] = $set2->{"bandwidthLimit"} if $set2->{"bandwidthLimit"};
                                next unless $bandwidthLimit[0] eq $bandwidthLimit[1];

                                my @active = ( q{}, q{} );
                                $active[0] = $set->{"active"}  if $set->{"active"};
                                $active[1] = $set2->{"active"} if $set2->{"active"};
                                next unless $active[0] eq $active[1];

                                $hostMap{ $set->{"key"} } = $set2->{"key"};
                            }
                        }
                    }
                }
            }
        }

        my ( $stsec, $stmin, $sthour, $stday, $stmonth, $styear ) = localtime();
        $stmonth += 1;
        $styear  += 1900;

        # XXX
        # JZ 8/24 - until we can get a date range from the service, start
        #           2 months back...
        $stmonth -= 2;
        if ( $stmonth <= 0 ) {
            $stmonth += 12;
            $styear -= 1;
        }

        my ( $dtsec, $dtmin, $dthour, $dtday, $dtmonth, $dtyear ) = localtime();
        $dtmonth += 1;
        $dtyear  += 1900;

        my @mon      = ( "", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" );
        my @sday     = ();
        my @smon     = ();
        my @syear    = ();
        my @dday     = ();
        my @dmon     = ();
        my @dyear    = ();
        my $selected = 0;
        for ( my $x = 1; $x < 13; $x++ ) {

            if ( $stmonth == $x ) {
                push @smon, { VALUE => $x, NAME => $mon[$x], SELECTED => 1 };
            }
            else {
                push @smon, { VALUE => $x, NAME => $mon[$x] };
            }
        }
        for ( my $x = 1; $x < 32; $x++ ) {
            if ( $stday == $x ) {
                push @sday, { VALUE => $x, NAME => $x, SELECTED => 1 };
            }
            else {
                push @sday, { VALUE => $x, NAME => $x };
            }
        }
        for ( my $x = 2000; $x < 2016; $x++ ) {
            if ( $styear == $x ) {
                push @syear, { VALUE => $x, NAME => $x, SELECTED => 1 };
            }
            else {
                push @syear, { VALUE => $x, NAME => $x };
            }
        }

        for ( my $x = 1; $x < 13; $x++ ) {
            if ( $dtmonth == $x ) {
                push @dmon, { VALUE => $x, NAME => $mon[$x], SELECTED => 1 };
            }
            else {
                push @dmon, { VALUE => $x, NAME => $mon[$x] };
            }
        }
        for ( my $x = 1; $x < 32; $x++ ) {
            if ( $dtday == $x ) {
                push @dday, { VALUE => $x, NAME => $x, SELECTED => 1 };
            }
            else {
                push @dday, { VALUE => $x, NAME => $x };
            }
        }
        for ( my $x = 2000; $x < 2016; $x++ ) {
            if ( $dtyear == $x ) {
                push @dyear, { VALUE => $x, NAME => $x, SELECTED => 1 };
            }
            else {
                push @dyear, { VALUE => $x, NAME => $x };
            }
        }

        my @pairs     = ();
        my @histPairs = ();
        my $counter   = 0;
        my %mark      = ();
        foreach my $src ( sort keys %list ) {
            foreach my $dst ( sort keys %{ $list{$src} } ) {
                foreach my $set ( @{ $list{$src}{$dst} } ) {
                    next if $mark{ $set->{"key"} };
                    if ( exists $set->{"active"} and $set->{"active"} ) {
                        push @pairs,
                            {
                            SADDRESS       => $set->{"saddr"},
                            SHOST          => $set->{"src"},
                            DADDRESS       => $set->{"daddr"},
                            DHOST          => $set->{"dst"},
                            PROTOCOL       => $set->{"protocol"},
                            TIMEDURATION   => $set->{"timeDuration"},
                            BUFFERLENGTH   => $set->{"bufferLength"},
                            WINDOWSIZE     => $set->{"windowSize"},
                            INTERVAL       => $set->{"interval"},
                            BANDWIDTHLIMIT => $set->{"bandwidthLimit"},
                            KEY            => $set->{"key"},
                            COUNT          => $counter,
                            SERVICE        => $service,
                            KEY2           => $hostMap{ $set->{"key"} }
                            };
                        $counter++;
                    }
                    else {
                        push @histPairs,
                            {
                            SADDRESS       => $set->{"saddr"},
                            SHOST          => $set->{"src"},
                            DADDRESS       => $set->{"daddr"},
                            DHOST          => $set->{"dst"},
                            PROTOCOL       => $set->{"protocol"},
                            TIMEDURATION   => $set->{"timeDuration"},
                            BUFFERLENGTH   => $set->{"bufferLength"},
                            WINDOWSIZE     => $set->{"windowSize"},
                            INTERVAL       => $set->{"interval"},
                            BANDWIDTHLIMIT => $set->{"bandwidthLimit"},
                            KEY            => $set->{"key"},
                            COUNT          => $counter,
                            SERVICE        => $service,
                            KEY2           => $hostMap{ $set->{"key"} },
                            SMON           => \@smon,
                            SDAY           => \@sday,
                            SYEAR          => \@syear,
                            DMON           => \@dmon,
                            DDAY           => \@dday,
                            DYEAR          => \@dyear
                            };
                        $counter++;
                    }
                    $mark{ $hostMap{ $set->{"key"} } } = 1 if $hostMap{ $set->{"key"} };
                }
            }
        }

        my @graph       = ();
        my $datacounter = 0;
        my $max         = 0;
        foreach my $d ( sort keys %data ) {
            my $din  = 0;
            my $dout = 0;
            $din  = ( $data{$d}{"in"}{"total"} / $data{$d}{"in"}{"count"} )   if $data{$d}{"in"}{"count"};
            $dout = ( $data{$d}{"out"}{"total"} / $data{$d}{"out"}{"count"} ) if $data{$d}{"out"}{"count"};
            $max  = $din                                                      if $din > $max;
            $max  = $dout                                                     if $dout > $max;
            push @graph, { c => $datacounter, location => $d, in => $din, out => $dout };
            $datacounter++;
        }
        my $temp = scaleValue( { value => $max } );
        foreach my $g ( @graph ) {
            $g->{"in"}  /= $temp->{"scale"};
            $g->{"out"} /= $temp->{"scale"};
        }

        $template->param(
            EVENTTYPE   => $eventType,
            SERVICE     => $service,
            HISTPAIRS   => \@histPairs,
            PAIRS       => \@pairs,
            GRAPHTOTAL  => $datacounter,
            GRAPH       => \@graph,
            GRAPHPREFIX => $temp->{"mod"}
        );
    }
    elsif ( $eventType eq "http://ggf.org/ns/nmwg/tools/owamp/2.0" or $eventType eq "http://ggf.org/ns/nmwg/characteristic/delay/summary/20070921" ) {
        my $sec = time;
        $template = HTML::Template->new( filename => "$RealBin/../etc/serviceTest_psb_owamp.tmpl" );

        my %lookup = ();
        foreach my $d ( @{ $result->{"data"} } ) {
            my $data = q{};
            eval { $data = $parser->parse_string( $d ); };
            if ( $EVAL_ERROR ) {
                $template = HTML::Template->new( filename => "$RealBin/../etc/serviceTest_error.tmpl" );
                $template->param( ERROR => "Could not parse XML response from MA <b><i>" . $service . "</i></b>." );
                print $template->output;
                exit( 1 );
            }

            my $metadataIdRef = $data->getDocumentElement->getAttribute( "metadataIdRef" );
            my $key           = extract( find( $data->getDocumentElement, ".//nmwg:parameter[\@name=\"maKey\"]", 1 ), 0 );
            $lookup{$metadataIdRef} = $key if $key and $metadataIdRef;
        }

        my %list = ();
        my %data = ();
        foreach my $md ( @{ $result->{"metadata"} } ) {
            my $metadata = q{};
            eval { $metadata = $parser->parse_string( $md ); };
            if ( $EVAL_ERROR ) {
                $template = HTML::Template->new( filename => "$RealBin/../etc/serviceTest_error.tmpl" );
                $template->param( ERROR => "Could not parse XML response from MA <b><i>" . $service . "</i></b>." );
                print $template->output;
                exit( 1 );
            }

            my $metadataId = $metadata->getDocumentElement->getAttribute( "id" );

            my $src   = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:endPointPair/nmwgt:src", 1 ), 0 );
            my $saddr = q{};
            my $shost = q{};

            if ( is_ipv4( $src ) ) {
                $saddr = $src;
                my $iaddr = Socket::inet_aton( $src );
                if ( defined $iaddr and $iaddr ) {
                    $shost = gethostbyaddr( $iaddr, Socket::AF_INET );
                }
                $shost = $src unless $shost;
            }
            elsif ( &Net::IPv6Addr::is_ipv6( $src ) ) {
                $saddr = $src;
                $shost = $src;

                # do something?
            }
            else {
                $shost = $src;
                my $packed_ip = gethostbyname( $src );
                if ( defined $packed_ip and $packed_ip ) {
                    $saddr = inet_ntoa( $packed_ip );
                }
                $saddr = $src unless $saddr;
            }

            my $dst   = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:endPointPair/nmwgt:dst", 1 ), 0 );
            my $daddr = q{};
            my $dhost = q{};
            if ( is_ipv4( $dst ) ) {
                $daddr = $dst;
                my $iaddr = Socket::inet_aton( $dst );
                if ( defined $iaddr and $iaddr ) {
                    $dhost = gethostbyaddr( $iaddr, Socket::AF_INET );
                }
                $dhost = $dst unless $dhost;
            }
            elsif ( &Net::IPv6Addr::is_ipv6( $dst ) ) {
                $daddr = $dst;
                $dhost = $dst;

                # do something?
            }
            else {
                $dhost = $dst;
                my $packed_ip = gethostbyname( $dst );
                if ( defined $packed_ip and $packed_ip ) {
                    $daddr = inet_ntoa( $packed_ip );
                }
                $daddr = $dst unless $daddr;
            }

            my %temp = ();
            my $params = find( $metadata->getDocumentElement, "./*[local-name()='parameters']/*[local-name()='parameter']", 0 );
            foreach my $p ( $params->get_nodelist ) {
                my $pName  = $p->getAttribute( "name" );
                my $pValue = q{};
                if ( lc( $pName ) eq "schedule" ) {
                    $pValue = extract( find( $p, ".//interval[\@type=\"exp\"]", 1 ), 0 );
                }
                else {
                    $pValue = extract( $p, 0 );
                }
                $temp{$pName} = $pValue if $pName and $pValue;
            }

            $temp{"key"}   = $lookup{$metadataId};
            $temp{"src"}   = $shost;
            $temp{"dst"}   = $dhost;
            $temp{"saddr"} = $saddr;
            $temp{"daddr"} = $daddr;

            unless ( exists $data{$shost}{$dhost} ) {
                $data{$shost}{$dhost}{"max"} = 0;
                $data{$shost}{$dhost}{"min"} = 0;
            }

            my @eventTypes = ();
            my $parser     = XML::LibXML->new();

            my $subject = "<nmwg:key id=\"key-1\"><nmwg:parameters id=\"parameters-key-1\"><nmwg:parameter name=\"maKey\">" . $lookup{$metadataId} . "</nmwg:parameter></nmwg:parameters></nmwg:key>";
            my $time    = 86400;

            my $result = $ma->setupDataRequest(
                {
                    start      => ( $sec - $time ),
                    end        => $sec,
                    subject    => $subject,
                    eventTypes => \@eventTypes
                }
            );

            my $doc1 = q{};
            eval { $doc1 = $parser->parse_string( $result->{"data"}->[0] ); };
            if ( $EVAL_ERROR ) {
                $template = HTML::Template->new( filename => "$RealBin/../etc/serviceTest_error.tmpl" );
                $template->param( ERROR => "Could not parse XML response from MA <b><i>" . $service . "</i></b>." );
                print $template->output;
                exit( 1 );
            }

            my $datum1 = find( $doc1->getDocumentElement, "./*[local-name()='datum']", 0 );
            if ( $datum1 ) {
                my $max = 0;
                my $min = 999999;
                foreach my $dt ( $datum1->get_nodelist ) {
                    my $maxval = $dt->getAttribute( "max_delay" );
                    $max = $maxval if $maxval and $maxval > $max;

                    my $minval = $dt->getAttribute( "min_delay" );
                    $min = $minval if $minval and $minval < $min;
                }
                if ( $max or ( $min < 999999 ) ) {
                    $temp{"active"} = 1;
                    $data{$shost}{$dhost}{"max"} = sprintf( "%.4f", ( $max * 1000 ) ) if $max;
                    $data{$shost}{$dhost}{"min"} = sprintf( "%.4f", ( $min * 1000 ) ) if $min < 999999;
                }
                else {
                    $temp{"active"} = 0;
                }
            }
            else {
                $temp{"active"} = 0;
            }

            push @{ $list{$shost}{$dhost} }, \%temp;
        }

        # figure out if hosts are equal - requires unrolling all of the options and comparing (ugh)
        my %hostMap = ();
        foreach my $src ( sort keys %list ) {
            foreach my $dst ( sort keys %{ $list{$src} } ) {
                foreach my $set ( @{ $list{$src}{$dst} } ) {
                    if ( $#{ $list{$src}{$dst} } > -1 and $#{ $list{$dst}{$src} } > -1 ) {
                        foreach my $set2 ( @{ $list{$dst}{$src} } ) {
                            if ( $set->{"src"} eq $set2->{"dst"} and $set->{"dst"} eq $set2->{"src"} and $set->{"saddr"} eq $set2->{"daddr"} and $set->{"daddr"} eq $set2->{"saddr"} ) {
                                my @bucket_width = ( q{}, q{} );
                                $bucket_width[0] = $set->{"bucket_width"}  if $set->{"bucket_width"};
                                $bucket_width[1] = $set2->{"bucket_width"} if $set2->{"bucket_width"};
                                next unless $bucket_width[0] eq $bucket_width[1];

                                my @count = ( q{}, q{} );
                                $count[0] = $set->{"count"}  if $set->{"count"};
                                $count[1] = $set2->{"count"} if $set2->{"count"};
                                next unless $count[0] eq $count[1];

                                my @schedule = ( q{}, q{} );
                                $schedule[0] = $set->{"schedule"}  if $set->{"schedule"};
                                $schedule[1] = $set2->{"schedule"} if $set2->{"schedule"};
                                next unless $schedule[0] eq $schedule[1];

                                my @DSCP = ( q{}, q{} );
                                $DSCP[0] = $set->{"DSCP"}  if $set->{"DSCP"};
                                $DSCP[1] = $set2->{"DSCP"} if $set2->{"DSCP"};
                                next unless $DSCP[0] eq $DSCP[1];

                                my @timeout = ( q{}, q{} );
                                $timeout[0] = $set->{"timeout"}  if $set->{"timeout"};
                                $timeout[1] = $set2->{"timeout"} if $set2->{"timeout"};
                                next unless $timeout[0] eq $timeout[1];

                                my @packet_padding = ( q{}, q{} );
                                $packet_padding[0] = $set->{"packet_padding"}  if $set->{"packet_padding"};
                                $packet_padding[1] = $set2->{"packet_padding"} if $set2->{"packet_padding"};
                                next unless $packet_padding[0] eq $packet_padding[1];

                                my @active = ( q{}, q{} );
                                $active[0] = $set->{"active"}  if $set->{"active"};
                                $active[1] = $set2->{"active"} if $set2->{"active"};
                                next unless $active[0] eq $active[1];

                                $hostMap{ $set->{"key"} } = $set2->{"key"};
                            }
                        }
                    }
                }
            }
        }

        my ( $stsec, $stmin, $sthour, $stday, $stmonth, $styear ) = localtime();
        $stmonth += 1;
        $styear  += 1900;

        # XXX
        # JZ 8/24 - until we can get a date range from the service, start
        #           2 months back...
        $stmonth -= 2;
        if ( $stmonth <= 0 ) {
            $stmonth += 12;
            $styear -= 1;
        }

        my ( $dtsec, $dtmin, $dthour, $dtday, $dtmonth, $dtyear ) = localtime();
        $dtmonth += 1;
        $dtyear  += 1900;

        my @mon      = ( "", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" );
        my @sday     = ();
        my @smon     = ();
        my @syear    = ();
        my @dday     = ();
        my @dmon     = ();
        my @dyear    = ();
        my $selected = 0;
        for ( my $x = 1; $x < 13; $x++ ) {

            if ( $stmonth == $x ) {
                push @smon, { VALUE => $x, NAME => $mon[$x], SELECTED => 1 };
            }
            else {
                push @smon, { VALUE => $x, NAME => $mon[$x] };
            }
        }
        for ( my $x = 1; $x < 32; $x++ ) {
            if ( $stday == $x ) {
                push @sday, { VALUE => $x, NAME => $x, SELECTED => 1 };
            }
            else {
                push @sday, { VALUE => $x, NAME => $x };
            }
        }
        for ( my $x = 2000; $x < 2016; $x++ ) {
            if ( $styear == $x ) {
                push @syear, { VALUE => $x, NAME => $x, SELECTED => 1 };
            }
            else {
                push @syear, { VALUE => $x, NAME => $x };
            }
        }

        for ( my $x = 1; $x < 13; $x++ ) {
            if ( $dtmonth == $x ) {
                push @dmon, { VALUE => $x, NAME => $mon[$x], SELECTED => 1 };
            }
            else {
                push @dmon, { VALUE => $x, NAME => $mon[$x] };
            }
        }
        for ( my $x = 1; $x < 32; $x++ ) {
            if ( $dtday == $x ) {
                push @dday, { VALUE => $x, NAME => $x, SELECTED => 1 };
            }
            else {
                push @dday, { VALUE => $x, NAME => $x };
            }
        }
        for ( my $x = 2000; $x < 2016; $x++ ) {
            if ( $dtyear == $x ) {
                push @dyear, { VALUE => $x, NAME => $x, SELECTED => 1 };
            }
            else {
                push @dyear, { VALUE => $x, NAME => $x };
            }
        }

        my @pairs     = ();
        my @histPairs = ();
        my $counter   = 0;
        my %mark      = ();
        foreach my $src ( sort keys %list ) {
            foreach my $dst ( sort keys %{ $list{$src} } ) {
                foreach my $set ( @{ $list{$src}{$dst} } ) {
                    next if $mark{ $set->{"key"} };
                    if ( exists $set->{"active"} and $set->{"active"} ) {
                        push @pairs,
                            {
                            SADDRESS => $set->{"saddr"},
                            SHOST    => $set->{"src"},
                            DADDRESS => $set->{"daddr"},
                            DHOST    => $set->{"dst"},
                            KEY      => $set->{"key"},
                            COUNT    => $counter,
                            SERVICE  => $service,
                            KEY2     => $hostMap{ $set->{"key"} }
                            };
                        $counter++;
                    }
                    else {
                        push @histPairs,
                            {
                            SADDRESS => $set->{"saddr"},
                            SHOST    => $set->{"src"},
                            DADDRESS => $set->{"daddr"},
                            DHOST    => $set->{"dst"},
                            KEY      => $set->{"key"},
                            COUNT    => $counter,
                            SERVICE  => $service,
                            KEY2     => $hostMap{ $set->{"key"} },
                            SMON     => \@smon,
                            SDAY     => \@sday,
                            SYEAR    => \@syear,
                            DMON     => \@dmon,
                            DDAY     => \@dday,
                            DYEAR    => \@dyear
                            };
                        $counter++;
                    }
                    $mark{ $hostMap{ $set->{"key"} } } = 1 if $hostMap{ $set->{"key"} };
                }
            }
        }

        my %colspan = ();
        foreach my $src ( sort keys %data ) {
            $colspan{$src} = 1;
            foreach my $dst ( sort keys %{ $data{$src} } ) {
                $colspan{$dst} = 1;
            }
        }

        my @matrixHeader = ();
        my @matrix       = ();
        foreach my $h1 ( sort keys %colspan ) {
            push @matrixHeader, { NAME => $h1 };
            my @temp = ();
            foreach my $h2 ( sort keys %colspan ) {
                $data{$h1}{$h2}{"min"} = "*" unless $data{$h1}{$h2}{"min"};
                $data{$h1}{$h2}{"max"} = "*" unless $data{$h1}{$h2}{"max"};
                push @temp, { MINVALUE => $data{$h1}{$h2}{"min"}, MAXVALUE => $data{$h1}{$h2}{"max"} };
            }
            push @matrix, { NAME => $h1, MATRIXCOLS => \@temp };
        }

        $template->param(
            EVENTTYPE     => $eventType,
            SERVICE       => $service,
            PAIRS         => \@pairs,
            HISTPAIRS     => \@histPairs,
            MATRIXCOLSPAN => ( scalar( keys %colspan ) + 1 ),
            MATRIXHEADER  => \@matrixHeader,
            MATRIX        => \@matrix
        );
    }
    elsif ( $eventType eq "http://ggf.org/ns/nmwg/tools/pinger/2.0/" or $eventType eq "http://ggf.org/ns/nmwg/tools/pinger/2.0" ) {
        $template = HTML::Template->new( filename => "$RealBin/../etc/serviceTest_pinger.tmpl" );

        my %lookup = ();
        foreach my $d ( @{ $result->{"data"} } ) {
            my $data = q{};
            eval { $data = $parser->parse_string( $d ); };
            if ( $EVAL_ERROR ) {
                $template = HTML::Template->new( filename => "$RealBin/../etc/serviceTest_error.tmpl" );
                $template->param( ERROR => "Could not parse XML response from MA <b><i>" . $service . "</i></b>." );
                print $template->output;
                exit( 1 );
            }

            my $metadataIdRef = $data->getDocumentElement->getAttribute( "metadataIdRef" );
            next unless $metadataIdRef;

            my $nmwg_key = find( $data->getDocumentElement, ".//nmwg:key", 1 );
            next unless ( $nmwg_key );

            my $key = $nmwg_key->getAttribute( "id" );
            $lookup{$metadataIdRef} = $key if $key;
        }

        my %list = ();
        foreach my $md ( @{ $result->{"metadata"} } ) {
            my $metadata = q{};
            eval { $metadata = $parser->parse_string( $md ); };
            if ( $EVAL_ERROR ) {
                $template = HTML::Template->new( filename => "$RealBin/../etc/serviceTest_error.tmpl" );
                $template->param( ERROR => "Could not parse XML response from MA <b><i>" . $service . "</i></b>." );
                print $template->output;
                exit( 1 );
            }

            my $metadataId = $metadata->getDocumentElement->getAttribute( "id" );

            my $src        = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:endPointPair/nmwgt:src",             1 ), 0 );
            my $dst        = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:endPointPair/nmwgt:dst",             1 ), 0 );
            my $packetsize = extract( find( $metadata->getDocumentElement, "./*[local-name()='parameters']/nmwg:parameter[\@name=\"packetSize\"]", 1 ), 0 );

            my %temp = ();
            $temp{"key"}        = $lookup{$metadataId};
            $temp{"src"}        = $src;
            $temp{"dst"}        = $dst;
            $temp{"packetsize"} = $packetsize ? $packetsize : 1000;
            $list{$src}{$dst}   = \%temp;
        }

        my @pairs   = ();
        my $counter = 0;
        foreach my $src ( sort keys %list ) {
            foreach my $dst ( sort keys %{ $list{$src} } ) {

                my $packed_ip   = gethostbyname( $list{$src}{$dst}->{"src"} );
                my $sip_address = $list{$src}{$dst}->{"src"};
                $sip_address = inet_ntoa( $packed_ip ) if defined $packed_ip;

                $packed_ip = gethostbyname( $list{$src}{$dst}->{"dst"} );
                my $dip_address = $list{$src}{$dst}->{"dst"};
                $dip_address = inet_ntoa( $packed_ip ) if defined $packed_ip;

                my $p_time = time - 43200;
                my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime( $p_time );
                my $p_start = sprintf "%04d-%02d-%02dT%02d:%02d:%02d", ( $year + 1900 ), ( $mon + 1 ), $mday, $hour, $min, $sec;
                $p_time += 43200;
                ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = gmtime( $p_time );
                my $p_end = sprintf "%04d-%02d-%02dT%02d:%02d:%02d", ( $year + 1900 ), ( $mon + 1 ), $mday, $hour, $min, $sec;

                push @pairs,
                    {
                    KEY      => $list{$src}{$dst}->{"key"},
                    SHOST    => $list{$src}{$dst}->{"src"},
                    SADDRESS => $sip_address,
                    DHOST    => $list{$src}{$dst}->{"dst"},
                    DADDRESS => $dip_address,
                    COUNT    => $counter,
                    SERVICE  => $service
                    };
                $counter++;
            }
        }

        $template->param(
            EVENTTYPE => $eventType,
            SERVICE   => $service,
            PAIRS     => \@pairs
        );
    }
    else {
        $template = HTML::Template->new( filename => "$RealBin/../etc/serviceTest_error.tmpl" );
        $template->param( ERROR => "Unrecognized eventType: \"" . $eventType . "\"." );
    }
}

print $template->output;

=head2 scaleValue ( { value } )

Given a value, return the value scaled to a magnitude.

=cut

sub scaleValue {
    my $parameters = validateParams( @_, { value => 1 } );
    my %result = ();
    if ( $parameters->{"value"} < 1000 ) {
        $result{"scale"} = 1;
        $result{"mod"}   = q{};
    }
    elsif ( $parameters->{"value"} < 1000000 ) {
        $result{"scale"} = 1000;
        $result{"mod"}   = "K";
    }
    elsif ( $parameters->{"value"} < 1000000000 ) {
        $result{"scale"} = 1000000;
        $result{"mod"}   = "M";
    }
    elsif ( $parameters->{"value"} < 1000000000000 ) {
        $result{"scale"} = 1000000000;
        $result{"mod"}   = "G";
    }
    return \%result;
}

__END__

=head1 SEE ALSO

L<CGI>, L<HTML::Template>, L<XML::LibXML>, L<Socket>, L<Data::Validate::IP>,
L<English>, L<Net::IPv6Addr>, L<perfSONAR_PS::Client::MA>,
L<perfSONAR_PS::Common>, L<perfSONAR_PS::Utils::ParameterValidation>

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

You should have received a copy of the Internet2 Intellectual Property Framework
along with this software.  If not, see
<http://www.internet2.edu/membership/ip.html>

=head1 COPYRIGHT

Copyright (c) 2007-2009, Internet2

All rights reserved.

=cut
