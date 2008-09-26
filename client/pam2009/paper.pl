#!/usr/bin/perl -w 

use strict;
use warnings;

=head1 NAME

paper.pl - Script used in conjunction w/ paper.conf to gather data from multiple
MA's and output into CSV format.  

=head1 DESCRIPTION

Consults paper.conf, reads the entries.  Makes queries to each MA, outputs the
results into CSV files.  

=cut

use Getopt::Long;
use Log::Log4perl qw(:easy);
use XML::LibXML;
use Date::Manip;
use Data::Validate::IP qw(is_ipv4);
use Socket;
use Config::General;
use Carp;

use lib "../../lib";

use perfSONAR_PS::Client::MA;
use perfSONAR_PS::Common qw( extract find );
use perfSONAR_PS::Transport;

my $DEBUGFLAG = q{};
my $HELP      = q{};
my $LOGOUTPUT = q{};
my %opts      = ();

my $ok = GetOptions(
    'verbose'  => \$DEBUGFLAG,
    'config=s' => \$opts{CONF},
    'logger=s' => \$opts{LOGGER},
    'start=s'  => \$opts{START},
    'len=s'    => \$opts{LENGTH},
    'help'     => \$HELP
);

if ( exists $opts{START} and $opts{START} ) {
    my $date = ParseDateString( $opts{START} );
    my $sec  = UnixDate( $date, "%s" );
    my $val  = $sec % 3600;
    $sec -= $val;
    $opts{START} = $sec;
}
else {
    my ( $sec, $frac ) = Time::HiRes::gettimeofday;
    my $val = $sec % 3600;
    $sec -= $val;
    $opts{START} = $sec;
}

if ( exists $opts{LENGTH} and $opts{LENGTH} ) {
    $opts{LENGTH} *= 3600;
}
else {

    # default to 1 hour
    $opts{LENGTH} = 3600*12;
}

if ( not $ok or $HELP ) {
    print "Usage: ./paper.pl\n";
    print "\t--verbose : Turn on debugging\n";
    print "\t--help : This message\n";
    print "\t--logger=file : File w/ logging information\n";
    print "\t--config=URL : Config file of hosts to contact\n";
    print "\t--start=time : Data Start Time\n";
    print "\t--len=URL : Length of time (in hours) from start time\n\n";
    exit(1);
}

my $logger = q{};
if ( not exists $opts{LOGGER} ) {
    use Log::Log4perl qw(:easy);

    my $output_level = $INFO;
    $output_level = $DEBUG if $DEBUGFLAG;

    my %logger_opts = (
        level  => $output_level,
        layout => '%d (%P) %p> %F{1}:%L %M - %m%n',
    );
    if ( defined $LOGOUTPUT and $LOGOUTPUT ) {
        $logger_opts{file} = $LOGOUTPUT;
    }

    Log::Log4perl->easy_init( \%logger_opts );
    $logger = get_logger("perfSONAR_PS");
}
else {
    use Log::Log4perl qw(get_logger :levels);

    my $output_level = $INFO;
    $output_level = $DEBUG if $DEBUGFLAG;

    Log::Log4perl->init( $opts{LOGGER} );
    $logger = get_logger("perfSONAR_PS");
    $logger->level($output_level);
}

unless ( exists $opts{CONF} and $opts{CONF} ) {
    $logger->error("Conf file not found, exiting.");
    exit(1);
}

system( "rm -f *csv" );

my $parser = XML::LibXML->new();
my $config = new Config::General( $opts{CONF} );
my %conf   = $config->getall;

foreach my $host ( keys %{ $conf{host} } ) {

    # each host

    $logger->info( "Querying \"" . $host . "\"" );
    my $ma = new perfSONAR_PS::Client::MA( { instance => $host } );

    my ( $host_name, $host_port, $host_endpoint ) = &perfSONAR_PS::Transport::splitURI($host);
    $host_endpoint =~ s/\//_/g;

    foreach my $md ( keys %{ $conf{host}->{$host}->{metadata} } ) {

        # constitutes a request.

        my $subject    = q{};
        my @eventTypes = ();
        my $eventType  = $conf{host}->{$host}->{metadata}->{$md}->{eventType};
        if ( $eventType eq "http://ggf.org/ns/nmwg/characteristic/utilization/2.0" ) {
            $subject = "    <netutil:subject xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\" id=\"s\">\n";
            $subject .= "      <nmwgt:interface xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";
            foreach my $field ( keys %{ $conf{host}->{$host}->{metadata}->{$md} } ) {
                if (   $field eq "ifAddress"
                    or $field eq "hostName"
                    or $field eq "ifName"
                    or $field eq "ifIndex"
                    or $field eq "direction"
                    or $field eq "capacity"
                    or $field eq "ifDescription"
                    or $field eq "description" )
                {
                    $subject .= "       <nmwgt:" . $field . ">" . $conf{host}->{$host}->{metadata}->{$md}->{$field} . "</nmwgt:" . $field . ">\n";
                }
            }
            $subject .= "      </nmwgt:interface>\n";
            $subject .= "    </netutil:subject>\n";
            push @eventTypes, $eventType;
        }
        elsif ( $eventType eq "http://ggf.org/ns/nmwg/tools/iperf/2.0" or $eventType eq "http://ggf.org/ns/nmwg/characteristics/bandwidth/acheiveable/2.0" ) {
            $subject = "    <iperf:subject xmlns:iperf=\"http://ggf.org/ns/nmwg/tools/iperf/2.0/\" id=\"subject\">\n";
            $subject .= "      <nmwgt:endPointPair xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";
            foreach my $field ( keys %{ $conf{host}->{$host}->{metadata}->{$md} } ) {
                if ( $field eq "src" or $field eq "dst" ) {
                    foreach my $field2 ( keys %{ $conf{host}->{$host}->{metadata}->{$md}->{$field} } ) {
                        $subject .= "       <nmwgt:" . $field . " value=\"" . $field2 . "\" ";
                        foreach my $field3 ( keys %{ $conf{host}->{$host}->{metadata}->{$md}->{$field}->{$field2} } ) {
                            $subject .= $field3 . "=\"" . $conf{host}->{$host}->{metadata}->{$md}->{$field}->{$field2}->{$field3} . "\" ";
                        }
                        $subject .= "/>\n";
                    }
                }
            }
            $subject .= "      </nmwgt:endPointPair>\n";
            $subject .= "    </iperf:subject>\n";
            push @eventTypes, $eventType;
        }
        elsif ( $eventType eq "http://ggf.org/ns/nmwg/tools/pinger/2.0/" or $eventType eq "http://ggf.org/ns/nmwg/tools/pinger/2.0" ) {
            $subject = "    <pinger:subject xmlns:pinger=\"http://ggf.org/ns/nmwg/tools/pinger/2.0/\">\n";
            $subject .= "      <nmwgt:endPointPair xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";
            foreach my $field ( keys %{ $conf{host}->{$host}->{metadata}->{$md} } ) {
                if ( $field eq "src" or $field eq "dst" ) {
                    foreach my $field2 ( keys %{ $conf{host}->{$host}->{metadata}->{$md}->{$field} } ) {
                        $subject .= "       <nmwgt:" . $field . " value=\"" . $field2 . "\" ";
                        foreach my $field3 ( keys %{ $conf{host}->{$host}->{metadata}->{$md}->{$field}->{$field2} } ) {
                            $subject .= $field3 . "=\"" . $conf{host}->{$host}->{metadata}->{$md}->{$field}->{$field2}->{$field3} . "\" ";
                        }
                        $subject .= "/>\n";
                    }
                }
            }
            $subject .= "      </nmwgt:endPointPair>\n";
            $subject .= "    </pinger:subject>\n";
            push @eventTypes, $eventType;
        }
        elsif ( $eventType eq "http://ggf.org/ns/nmwg/tools/owamp/2.0" or $eventType eq "http://ggf.org/ns/nmwg/characteristic/delay/summary/20070921" ) {
            $subject = "    <owamp:subject xmlns:owamp=\"http://ggf.org/ns/nmwg/tools/owamp/2.0/\" id=\"subject\">\n";
            $subject .= "      <nmwgt:endPointPair xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\" />\n";
            $subject .= "    </owamp:subject>\n";
            push @eventTypes, $eventType;
        }
        else {
            $logger->error("EventType not found, exiting.");
            exit(1);
        }

        my $result = $ma->metadataKeyRequest(
            {
                subject    => $subject,
                eventTypes => \@eventTypes
            }
        );
        unless ( $#{ $result->{"metadata"} } > -1 ) {
            $logger->error( $host . " experienced an error, service may be unreachable." );
            exit(1);
        }

        my $metadata = $parser->parse_string( $result->{"metadata"}->[0] );
        my $et = extract( find( $metadata->getDocumentElement, ".//nmwg:eventType", 1 ), 0 );

        if ( $et =~ m/^error/ ) {
            $logger->error( $host . " experienced an error, check configuration and contents of store file." );
            exit(1);
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

                foreach my $host ( sort keys %list ) {
                    foreach my $name ( sort keys %{ $list{$host} } ) {

                        my $t1 = ParseDateString( "epoch " . ( $opts{START} - $opts{LENGTH} ) );
                        my $startTime = UnixDate( $t1, "%Y-%m-%d_%H:%M:%S" );
                        $t1 = ParseDateString( "epoch " . $opts{START} );
                        my $endTime = UnixDate( $t1, "%Y-%m-%d_%H:%M:%S" );

                        if ( exists $list{$host}{$name}->{"hostName"} and $list{$host}{$name}->{"hostName"} ) {
                            if ( is_ipv4( $list{$host}{$name}->{"hostName"} ) ) {
                                unless ( exists $list{$host}{$name}->{"ipAddress"} and $list{$host}{$name}->{"ipAddress"} ) {
                                    $list{$host}{$name}->{"ipAddress"} = $list{$host}{$name}->{"hostName"};
                                }

                                my $display = $list{$host}{$name}->{"hostName"};
                                $display =~ s/:.*$//;
                                my $iaddr = Socket::inet_aton($display);
                                my $shost = gethostbyaddr( $iaddr, Socket::AF_INET );
                                if ($shost) {
                                    $list{$host}{$name}->{"hostName"} = $shost;
                                }
                            }
                        }

                        if ( exists $list{$host}{$name}->{"ipAddress"} and $list{$host}{$name}->{"ipAddress"} ) {
                            unless ( is_ipv4( $list{$host}{$name}->{"ipAddress"} ) ) {
                                unless ( exists $list{$host}{$name}->{"hostName"} and $list{$host}{$name}->{"hostName"} ) {
                                    $list{$host}{$name}->{"hostName"} = $list{$host}{$name}->{"ipAddress"};
                                }

                                my $packed_ip = gethostbyname( $list{$host}{$name}->{"ipAddress"} );
                                if ( defined $packed_ip ) {
                                    my $ip_address = inet_ntoa($packed_ip);
                                    $list{$host}{$name}->{"ipAddress"} = Socket::inet_ntoa($packed_ip);
                                }
                            }
                        }

                        if ( exists $list{$host}{$name}->{"ifAddress"} and $list{$host}{$name}->{"ifAddress"} ) {
                            unless ( is_ipv4( $list{$host}{$name}->{"ifAddress"} ) ) {

                                my $packed_ip = gethostbyname( $list{$host}{$name}->{"ifAddress"} );
                                if ( defined $packed_ip ) {
                                    my $ip_address = inet_ntoa($packed_ip);
                                    $list{$host}{$name}->{"ifAddress"} = Socket::inet_ntoa($packed_ip);
                                }
                            }
                        }

                        # 'in' data
                        my $subject1 = "  <nmwg:key id=\"key-1\">\n";
                        $subject1 .= "    <nmwg:parameters id=\"parameters-key-1\">\n";
                        $subject1 .= "      <nmwg:parameter name=\"maKey\">" . $list{$host}{$name}->{"key1"} . "</nmwg:parameter>\n";
                        $subject1 .= "    </nmwg:parameters>\n";
                        $subject1 .= "  </nmwg:key>  \n";

                        my $result = $ma->setupDataRequest(
                            {
                                start                 => ( $opts{START} - $opts{LENGTH} ) - 15,
                                end                   => $opts{START} - 15,
                                resolution            => 15,
                                consolidationFunction => "AVERAGE",
                                subject               => $subject1,
                                eventTypes            => \@eventTypes
                            }
                        );

                        # 'out' data
                        my $subject2 = "  <nmwg:key id=\"key-2\">\n";
                        $subject2 .= "    <nmwg:parameters id=\"parameters-key-2\">\n";
                        $subject2 .= "      <nmwg:parameter name=\"maKey\">" . $list{$host}{$name}->{"key2"} . "</nmwg:parameter>\n";
                        $subject2 .= "    </nmwg:parameters>\n";
                        $subject2 .= "  </nmwg:key>  \n";
                        my $result2 = $ma->setupDataRequest(
                            {
                                start                 => ( $opts{START} - $opts{LENGTH} ) - 15,
                                end                   => $opts{START} - 15,
                                resolution            => 15,
                                consolidationFunction => "AVERAGE",
                                subject               => $subject2,
                                eventTypes            => \@eventTypes
                            }
                        );

                        unless ( ( exists $result->{eventType} and $result->{eventType} =~ m/^error/ ) or ( exists $result2->{eventType} and $result2->{eventType} =~ m/^error/ ) ) {
                            my $temp = $list{$host}{$name}->{"ifName"};
                            $temp =~ s/\///g;
                            $temp =~ s/ /_/g;

                            open( CSV1, ">SNMP_" . $host_name . "_" . $host_port . "_" . $host_endpoint . "-" . $list{$host}{$name}->{"hostName"} . "_" . $temp . "-" . $startTime . "_" . $endTime . ".csv" ) or croak "Can't open: $!";
                            print CSV1 "ipAddress,hostName,ifName,ifDescription,ifAddress,capacity (M)\n";
                            print CSV1 $list{$host}{$name}->{"ipAddress"}, ",", $list{$host}{$name}->{"hostName"}, ",", $list{$host}{$name}->{"ifName"}, ",", $list{$host}{$name}->{"ifDescription"}, ",", $list{$host}{$name}->{"ifAddress"}, ",",
                                eval( $list{$host}{$name}->{"capacity"} / 1000000 ) . "\n\n";

                            my $doc1 = $parser->parse_string( $result->{"data"}->[0] );
                            my $datum1 = find( $doc1->getDocumentElement, "./*[local-name()='datum']", 0 );

                            my $doc2 = $parser->parse_string( $result2->{"data"}->[0] );
                            my $datum2 = find( $doc2->getDocumentElement, "./*[local-name()='datum']", 0 );

                            if ( $datum1 and $datum2 ) {
                                my %store = ();
                                foreach my $dt ( $datum1->get_nodelist ) {
                                    $store{ $dt->getAttribute("timeValue") }{"in"} = $dt->getAttribute("value") if $dt->getAttribute("timeValue") and $dt->getAttribute("value");
                                }
                                foreach my $dt ( $datum2->get_nodelist ) {
                                    $store{ $dt->getAttribute("timeValue") }{"out"} = $dt->getAttribute("value") if $dt->getAttribute("timeValue") and $dt->getAttribute("value");
                                }

                                print CSV1 "unix time,iso time,in bps, out bps\n";
                                foreach my $time ( sort keys %store ) {
                                    next unless $time;
                                    my $date = ParseDateString( "epoch " . $time );
                                    my $date2 = UnixDate( $date, "%Y-%m-%d %H:%M:%S" );
                                    print CSV1 $time, ",", $date2, ",";

                                    if ( exists $store{$time}{"in"} and $store{$time}{"in"} ) {
                                        print CSV1 $store{$time}{"in"}, ",";
                                    }
                                    else {
                                        print CSV1 ",";
                                    }
                                    if ( exists $store{$time}{"out"} and $store{$time}{"out"} ) {
                                        print CSV1 $store{$time}{"out"}, "\n";
                                    }
                                    else {
                                        print CSV1 "\n";
                                    }
                                }
                            }
                            close(CSV1);
                        }
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

                    my $src = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:endPointPair/nmwgt:src", 1 ), 0 );
                    my $dst = extract( find( $metadata->getDocumentElement, "./*[local-name()='subject']/nmwgt:endPointPair/nmwgt:dst", 1 ), 0 );

                    my %temp = ();
                    $temp{"key"}      = $lookup{$metadataId};
                    $temp{"src"}      = $src;
                    $temp{"dst"}      = $dst;
                    $list{$src}{$dst} = \%temp;
                }

                foreach my $src ( sort keys %list ) {
                    foreach my $dst ( sort keys %{ $list{$src} } ) {
                        my $src_addr  = q{};
                        my $src_host  = q{};
                        my $dst_addr  = q{};
                        my $dst_host  = q{};
                        my $t1        = ParseDateString( "epoch " . ( $opts{START} - $opts{LENGTH} ) );
                        my $startTime = UnixDate( $t1, "%Y-%m-%d_%H:%M:%S" );
                        $t1 = ParseDateString( "epoch " . $opts{START} );
                        my $endTime = UnixDate( $t1, "%Y-%m-%d_%H:%M:%S" );

                        $src_addr = $list{$src}{$dst}->{"src"};

                        my $display = $list{$src}{$dst}->{"src"};
                        $display =~ s/:.*$//;
                        my $iaddr = Socket::inet_aton($display);
                        my $shost = gethostbyaddr( $iaddr, Socket::AF_INET );
                        if ($shost) {
                            $src_host = $shost;
                        }
                        else {
                            $src_host = $list{$src}{$dst}->{"src"};
                        }

                        $dst_addr = $list{$src}{$dst}->{"dst"};

                        my $display2 = $list{$src}{$dst}->{"dst"};
                        $display2 =~ s/:.*$//;
                        my $iaddr2 = Socket::inet_aton($display2);
                        my $dhost = gethostbyaddr( $iaddr2, Socket::AF_INET );
                        if ($dhost) {
                            $dst_host = $dhost;
                        }
                        else {
                            $dst_host = $list{$src}{$dst}->{"dst"};
                        }

                        my $subject1 = "  <nmwg:key id=\"key-1\">\n";
                        $subject1 .= "    <nmwg:parameters id=\"parameters-key-1\">\n";
                        $subject1 .= "      <nmwg:parameter name=\"maKey\">" . $list{$src}{$dst}->{"key"} . "</nmwg:parameter>\n";
                        $subject1 .= "    </nmwg:parameters>\n";
                        $subject1 .= "  </nmwg:key>  \n";

                        my $result = $ma->setupDataRequest(
                            {
                                start      => ( $opts{START} - $opts{LENGTH} ),
                                end        => $opts{START},
                                subject    => $subject1,
                                eventTypes => \@eventTypes
                            }
                        );

                        unless ( exists $result->{eventType} and $result->{eventType} =~ m/^error/ ) {
                            open( CSV, ">pSB_" . $host_name . "_" . $host_port . "_" . $host_endpoint . "-" . $src_addr . "_" . $dst_addr . "-" . $startTime . "_" . $endTime . ".csv" ) or croak "Can't open: $!";
                            print CSV "source address, source host, destination address, destination host\n";
                            print CSV $src_addr, ",", $src_host, ",", $dst_addr, ",", $dst_host, "\n\n";

                            my $doc1 = $parser->parse_string( $result->{"data"}->[0] );
                            my $datum1 = find( $doc1->getDocumentElement, "./*[local-name()='datum']", 0 );

                            if ( $datum1 ) {
                                my %store = ();
                                foreach my $dt ( $datum1->get_nodelist ) {
                                    my $secs = UnixDate( $dt->getAttribute("timeValue"), "%s" );
                                    #$store{$secs} = eval( $dt->getAttribute("throughput") );
                                    $store{$secs} = $dt->getAttribute("throughput");
                                }
                                print CSV "unix time,iso time,bandwidth bps\n";
                                foreach my $time ( sort keys %store ) {
                                    next unless $time;
                                    my $date = ParseDateString( "epoch " . $time );
                                    my $date2 = UnixDate( $date, "%Y-%m-%d %H:%M:%S" );
                                    print CSV $time, ",", $date2, ",";

                                    if ( exists $store{$time} and $store{$time} ) {
                                        print CSV $store{$time}, "\n";
                                    }
                                    else {
                                        print CSV "\n";
                                    }
                                }
                            }
                            close(CSV);
                        }
                    }
                }
            }
            elsif ( $eventType eq "http://ggf.org/ns/nmwg/tools/pinger/2.0/" or $eventType eq "http://ggf.org/ns/nmwg/tools/pinger/2.0" ) {
                my %lookup = ();
                foreach my $d ( @{ $result->{"data"} } ) {
                    my $data          = $parser->parse_string($d);
                    my $metadataIdRef = $data->getDocumentElement->getAttribute("metadataIdRef");
                    my $key           = find( $data->getDocumentElement, ".//*[local-name()='key']", 1 );
                    my $kid           = $key->getAttribute("id");
                    $lookup{$metadataIdRef} = $kid if $kid and $metadataIdRef;
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

                foreach my $src ( sort keys %list ) {
                    foreach my $dst ( sort keys %{ $list{$src} } ) {
                        my $src_host  = q{};
                        my $dst_host  = q{};
                        my $t1        = ParseDateString( "epoch " . ( $opts{START} - $opts{LENGTH} ) );
                        my $startTime = UnixDate( $t1, "%Y-%m-%d_%H:%M:%S" );
                        $t1 = ParseDateString( "epoch " . $opts{START} );
                        my $endTime = UnixDate( $t1, "%Y-%m-%d_%H:%M:%S" );

                        $src_host = $list{$src}{$dst}->{"src"};

                        $dst_host = $list{$src}{$dst}->{"dst"};

                        my $subject1 = "<pinger:subject id=\"subj\" xmlns:pinger=\"http://ggf.org/ns/nmwg/tools/pinger/2.0/\">\n";
                        $subject1 .= "  <nmwgt:endPointPair xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";
                        $subject1 .= "    <nmwgt:src value=\"" . $src_host . "\" type=\"hostname\" />\n";
                        $subject1 .= "    <nmwgt:dst value=\"" . $dst_host . "\" type=\"hostname\" />\n";
                        $subject1 .= "  </nmwgt:endPointPair>\n";
                        $subject1 .= "</pinger:subject>\n";
                        $subject1 .= "<nmwg:key id=\"" . $list{$src}{$dst}->{"key"} . "\"/>\n";

                        my $parameter1 = "<pinger:parameters id=\"params\" xmlns:pinger=\"http://ggf.org/ns/nmwg/tools/pinger/2.0/\">\n";
                        $parameter1 .= "  <nmwg:parameter name=\"startTime\">" . ( $opts{START} - $opts{LENGTH} ) . "</nmwg:parameter>\n";
                        $parameter1 .= "  <nmwg:parameter name=\"endTime\">" . $opts{START} . "</nmwg:parameter>\n";
                        $parameter1 .= "  <nmwg:parameter name=\"consolidationFunction\">AVERAGE</nmwg:parameter>\n";
                        $parameter1 .= "  <nmwg:parameter name=\"resolution\">100</nmwg:parameter>\n";
                        $parameter1 .= "</pinger:parameters>\n";

                        my $result = $ma->setupDataRequest(
                            {
                                parameterblock => $parameter1,
                                subject        => $subject1,
                                eventTypes     => \@eventTypes
                            }
                        );

                        unless ( exists $result->{eventType} and $result->{eventType} =~ m/^error/ ) {

                            open( CSV, ">PingER_" . $host_name . "_" . $host_port . "_" . $host_endpoint . "-" . $src_host . "_" . $dst_host . "-" . $startTime . "_" . $endTime . ".csv" ) or croak "Can't open: $!";
                            print CSV "source host, destination host\n";
                            print CSV $src_host, ",", $dst_host, "\n\n";

                            my $doc1 = $parser->parse_string( $result->{"data"}->[0] );
                            my $ct1 = find( $doc1->getDocumentElement, "./*[local-name()='commonTime']", 0 );

                            if ($ct1) {
                                my %store = ();
                                foreach my $ct ( $ct1->get_nodelist ) {
                                    my $secs = $ct->getAttribute("value");

                                    my $datum = find( $ct, "./*[local-name()='datum']", 0 );
                                    foreach my $dt ( $datum->get_nodelist ) {
                                        my $name  = $dt->getAttribute("name");
                                        my $value = $dt->getAttribute("value");
                                        #$store{$secs}{$name} = eval($value);
                                        $store{$secs}{$name} = $value;
                                    }
                                }

                                print CSV "unix time,iso time,minRtt,maxRtt,medianRtt,meanRtt,iqrIpd,maxIpd,meanIpd\n";
                                my @array = ( "minRtt", "maxRtt", "medianRtt", "meanRtt", "iqrIpd", "maxIpd", "meanIpd" );
                                foreach my $time ( sort keys %store ) {
                                    next unless $time;
                                    my $date = ParseDateString( "epoch " . $time );
                                    my $date2 = UnixDate( $date, "%Y-%m-%d %H:%M:%S" );
                                    print CSV $time, ",", $date2;
                                    foreach my $field (@array) {
                                        if ( exists $store{$time}{$field} and $store{$time}{$field} ) {
                                            print CSV ",", $store{$time}{$field};
                                        }
                                        else {
                                            print CSV ",";
                                        }
                                    }
                                    print CSV "\n";
                                }
                            }
                            close(CSV);
                        }
                    }
                }
            }
            elsif ( $eventType eq "http://ggf.org/ns/nmwg/tools/owamp/2.0" or $eventType eq "http://ggf.org/ns/nmwg/characteristic/delay/summary/20070921" ) {
                $logger->error( "No support for eventType \"" . $eventType . "\" yet" );
                exit(1);
            }
            else {
                $logger->error( "No support for eventType \"" . $eventType . "\" yet" );
                exit(1);
            }
        }
    }
}


__END__

=head1 SEE ALSO

L<Getopt::Long>, L<Log::Log4perl>, L<XML::LibXML>, L<Date::Manip>,
L<Data::Validate::IP>, L<Socket>, L<Config::General>, L<Carp>,
L<perfSONAR_PS::Client::MA>, L<perfSONAR_PS::Common>, L<perfSONAR_PS::Transport>

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

Copyright (c) 2008, Internet2

All rights reserved.

=cut
