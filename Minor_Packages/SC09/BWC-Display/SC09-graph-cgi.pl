#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

SC09-graph-cgi.pl - Generates CGIs full of JSON data for a dashboard application.

=head1 DESCRIPTION

Given some SNMP MA interface information, extract the values and create JSON
data suitable for use in a dashboard application. 

=cut

use CGI;
use XML::LibXML;
use Date::Manip;
use English qw( -no_match_vars );

#use FindBin qw($RealBin);
#my $basedir = "$RealBin/";
#use lib "$RealBin/../lib";

use lib "/home/zurawski/perfSONAR-PS/Shared/lib";

use perfSONAR_PS::Client::MA;
use perfSONAR_PS::Common qw( extract find );
use perfSONAR_PS::Utils::ParameterValidation;

my @list = ();

# UDel
# dnoc-rtr-1739 Eth1/26 (using Internet2 connection)
# dnoc-rtr-2488 xe-3/0/7 (using Vanderbilt connection)
push @list,
    {
    file       => "bwc-udel.cgi",
    url        => "http://monitor.sc09.org:9990/perfSONAR_PS/services/SNMPMA",
    interfaces => [
        {
            hostName => "dnoc-rtr-1739.sc09.org",
            ifName   => "Ethernet1/26",
        },
        {
            hostName => "dnoc-rtr-2488.sc09.org",
            ifName   => "xe-3/0/7",
        }
    ],
    length     => 3600,
    resolution => 1
    };
push @list,
    {
    file       => "bwc-vandy.cgi",
    url        => "http://monitor.sc09.org:9990/perfSONAR_PS/services/SNMPMA",
    interfaces => [
        {
            hostName => "dnoc-rtr-2488.sc09.org",
            ifName   => "xe-3/0/7",
        }
    ],
    length     => 3600,
    resolution => 1
    };
push @list,
    {
    file       => "bwc-internet2.cgi",
    url        => "http://monitor.sc09.org:9990/perfSONAR_PS/services/SNMPMA",
    interfaces => [
        {
            hostName => "dnoc-rtr-1739.sc09.org",
            ifName   => "Ethernet1/26",
        }
    ],
    length     => 3600,
    resolution => 1
    };

# UIC
# dnoc-rtr-1739 Eth1/17
# dnoc-rtr-1739 Eth1/18
push @list,
    {
    file       => "bwc-uic.cgi",
    url        => "http://monitor.sc09.org:9990/perfSONAR_PS/services/SNMPMA",
    interfaces => [
        {
            hostName => "dnoc-rtr-1739.sc09.org",
            ifName   => "Ethernet1/17",
        },
        {
            hostName => "dnoc-rtr-1739.sc09.org",
            ifName   => "Ethernet1/18",
        }
    ],
    length     => 3600,
    resolution => 1
    };

# ANL
# dnoc-rtr-2488 xe-3/0/3 (using Utah connections)
# dnoc-rtr-2488 xe-3/0/4
push @list,
    {
    file       => "bwc-anl.cgi",
    url        => "http://monitor.sc09.org:9990/perfSONAR_PS/services/SNMPMA",
    interfaces => [
        {
            hostName => "dnoc-rtr-2488.sc09.org",
            ifName   => "xe-3/0/3",
        },
        {
            hostName => "dnoc-rtr-2488.sc09.org",
            ifName   => "xe-3/0/4",
        }
    ],
    length     => 3600,
    resolution => 1
    };

# Caltech
push @list,
    {
    file       => "bwc-caltech.cgi",
    url        => "http://monitor.sc09.org:9990/perfSONAR_PS/services/SNMPMA",
    interfaces => [
        {
            hostName => "2135J-scinet.sc09.org",
            ifName   => "Ethernet1/1",
        },
        {
            hostName => "2135J-scinet.sc09.org",
            ifName   => "Ethernet1/2",
        },
        {
            hostName => "2135J-scinet.sc09.org",
            ifName   => "Ethernet2/10",
        },
        {
            hostName => "2135J-scinet.sc09.org",
            ifName   => "Ethernet2/2",
        },
        {
            hostName => "2135J-scinet.sc09.org",
            ifName   => "Ethernet2/9",
        },
        {
            hostName => "2135J-scinet.sc09.org",
            ifName   => "Ethernet1/10",
        },
        {
            hostName => "2135J-scinet.sc09.org",
            ifName   => "Ethernet3/2",
        },
        {
            hostName => "2135J-scinet.sc09.org",
            ifName   => "Ethernet1/9",
        },
        {
            hostName => "2135J-scinet.sc09.org",
            ifName   => "Ethernet2/1",
        },
        {
            hostName => "2135J-scinet.sc09.org",
            ifName   => "Ethernet4/1",
        },
        {
            hostName => "2135J-scinet.sc09.org",
            ifName   => "Ethernet4/2",
        },
        {
            hostName => "2135J-scinet.sc09.org",
            ifName   => "Ethernet4/9",
        },
        {
            hostName => "2135J-scinet.sc09.org",
            ifName   => "Ethernet4/18",
        },
        {
            hostName => "2135J-scinet.sc09.org",
            ifName   => "Ethernet3/10",
        },
        {
            hostName => "2135J-scinet.sc09.org",
            ifName   => "Ethernet4/10",
        }
    ],
    length     => 3600,
    resolution => 1
    };

# Tokyo
# dnoc-rtr-1050 ethernet 4/4
push @list,
    {
    file       => "bwc-tokyo.cgi",
    url        => "http://monitor.sc09.org:9990/perfSONAR_PS/services/SNMPMA",
    interfaces => [
        {
            hostName => "dnoc-rtr-1050.sc09.org",
            ifName   => "10GigabitEthernet4/4",
        }
    ],
    length     => 3600,
    resolution => 1
    };

my $mul = 1;

#my $div = 1048576;
my $div = 1073741824;

while ( 1 ) {

    foreach my $site ( @list ) {
        my $output = q{};
        $output = "#!/usr/bin/perl\n\n";
        $output .= "print \"Content-type: application/json\\n\\n\";\n\n";

        my $url        = $site->{"url"};
        my $length     = $site->{"length"};
        my $resolution = $site->{"resolution"};

        my $sec = time;
        $sec -= ( $sec % $resolution );

        my %store = ();
        foreach my $interface ( @{ $site->{"interfaces"} } ) {
            my $ifAddress = $interface->{"ifAddress"};
            my $hostName  = $interface->{"hostName"};
            my $ifName    = $interface->{"ifName"};

            my $subject = "    <netutil:subject xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\" id=\"subject.1\">\n";
            $subject .= "      <nmwgt:interface xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";
            $subject .= "        <nmwgt:ifAddress>" . $ifAddress . "</nmwgt:ifAddress>\n" if $ifAddress;
            $subject .= "        <nmwgt:hostName>" . $hostName . "</nmwgt:hostName>\n" if $hostName;
            $subject .= "        <nmwgt:ifName>" . $ifName . "</nmwgt:ifName>\n" if $ifName;
            $subject .= "        <nmwgt:direction>in</nmwgt:direction>\n";
            $subject .= "      </nmwgt:interface>\n";
            $subject .= "    </netutil:subject>\n";

            my $ma = new perfSONAR_PS::Client::MA( { instance => $url } );

            my @eventTypes = ( "http://ggf.org/ns/nmwg/characteristic/utilization/2.0" );
            my $parser     = XML::LibXML->new();

            my $result = $ma->setupDataRequest(
                {
                    start                 => ( $sec - $length ),
                    end                   => $sec,
                    resolution            => $resolution,
                    consolidationFunction => "AVERAGE",
                    subject               => $subject,
                    eventTypes            => \@eventTypes
                }
            );

            my $doc1 = q{};
            eval { $doc1 = $parser->parse_string( $result->{"data"}->[0] ); };
            if ( $EVAL_ERROR ) {
                exit( 1 );
            }
            my $datum1 = find( $doc1->getDocumentElement, "./*[local-name()='datum']", 0 );

            $subject = "    <netutil:subject xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\" id=\"subject.1\">\n";
            $subject .= "      <nmwgt:interface xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";
            $subject .= "        <nmwgt:ifAddress>" . $ifAddress . "</nmwgt:ifAddress>\n" if $ifAddress;
            $subject .= "        <nmwgt:hostName>" . $hostName . "</nmwgt:hostName>\n" if $hostName;
            $subject .= "        <nmwgt:ifName>" . $ifName . "</nmwgt:ifName>\n" if $ifName;
            $subject .= "        <nmwgt:direction>out</nmwgt:direction>\n";
            $subject .= "      </nmwgt:interface>\n";
            $subject .= "    </netutil:subject>\n";

            my $result2 = $ma->setupDataRequest(
                {
                    start                 => ( $sec - $length ),
                    end                   => $sec,
                    resolution            => $resolution,
                    consolidationFunction => "AVERAGE",
                    subject               => $subject,
                    eventTypes            => \@eventTypes
                }
            );

            my $doc2 = q{};
            eval { $doc2 = $parser->parse_string( $result2->{"data"}->[0] ); };
            if ( $EVAL_ERROR ) {
                exit( 1 );
            }
            my $datum2 = find( $doc2->getDocumentElement, "./*[local-name()='datum']", 0 );

            my $counter = 0;
            my $inUnit  = q{};
            my $outUnit = q{};
            foreach my $dt ( $datum1->get_nodelist ) {
                my $t = $dt->getAttribute( "timeValue" );
                my $v = $dt->getAttribute( "value" );
                if ( $v and ( $v > ( 10 * $div ) ) ) {
                    $v = $div * 10;
                }
                if ( $t and exists $store{$t}{"in"} ) {
                    $store{$t}{"in"} += eval( $v ) if $v;
                }
                else {
                    $store{$t}{"in"} = eval( $v ) if $v;
                }
                $inUnit = $dt->getAttribute( "valueUnits" ) unless $inUnit;
            }
            foreach my $dt ( $datum2->get_nodelist ) {
                my $t = $dt->getAttribute( "timeValue" );
                my $v = $dt->getAttribute( "value" );
                if ( $v and ( $v > ( 10 * $div ) ) ) {
                    $v = $div * 10;
                }
                if ( $t and exists $store{$t}{"out"} ) {
                    $store{$t}{"out"} += eval( $v ) if $v;
                }
                else {
                    $store{$t}{"out"} = eval( $v ) if $v;
                }
                $outUnit = $dt->getAttribute( "valueUnits" ) unless $outUnit;
            }

            if ( $inUnit and $outUnit and ( $inUnit eq $outUnit ) ) {
                if ( $inUnit =~ m/.*Bps$/ ) {

                    #                    $mul = 8;
                }
            }
        }

        my $counter = 0;
        foreach my $a ( keys %store ) {
            $counter++;
        }

        $output .= "print \"{\\\"Results\\\":\\n\";\n";
        $output .= "print \"[\\n\";\n";

        my $counter2 = 0;
        foreach my $time ( sort keys %store ) {
            my $date  = ParseDateString( "epoch " . $time );
            my $date2 = UnixDate( $date, "%Y-%m-%d %H:%M:%S" );
            my @array = split( / /, $date2 );
            my @year  = split( /-/, $array[0] );
            my @time  = split( /:/, $array[1] );
            if ( $#year > 1 and $#time > 1 and ( exists $store{$time}{"in"} and $store{$time}{"in"} and exists $store{$time}{"out"} and $store{$time}{"out"} ) ) {

                $store{$time}{"in"}  *= $mul;
                $store{$time}{"out"} *= $mul;
                $store{$time}{"in"}  /= $div;
                $store{$time}{"out"} /= $div;
                if ( $counter2 == ( $counter - 1 ) ) {
                    $output
                        .= "print \"{\\\"date\\\":\\\""
                        . sprintf( "%02d", ( $year[1] ) ) . "/"
                        . sprintf( "%02d", $year[2] ) . "/"
                        . $year[0] . " "
                        . sprintf( "%02d", $time[0] ) . ":"
                        . sprintf( "%02d", $time[1] ) . ":"
                        . sprintf( "%02d", $time[2] )
                        . "\\\", \\\"inspeed\\\":\\\""
                        . sprintf( "%.2f", $store{$time}{"in"} )
                        . "\\\", \\\"outspeed\\\":\\\""
                        . sprintf( "%.2f", $store{$time}{"out"} )
                        . "\\\"}\\n\";\n";
                }
                else {
                    $output
                        .= "print \"{\\\"date\\\":\\\""
                        . sprintf( "%02d", ( $year[1] ) ) . "/"
                        . sprintf( "%02d", $year[2] ) . "/"
                        . $year[0] . " "
                        . sprintf( "%02d", $time[0] ) . ":"
                        . sprintf( "%02d", $time[1] ) . ":"
                        . sprintf( "%02d", $time[2] )
                        . "\\\", \\\"inspeed\\\":\\\""
                        . sprintf( "%.2f", $store{$time}{"in"} )
                        . "\\\", \\\"outspeed\\\":\\\""
                        . sprintf( "%.2f", $store{$time}{"out"} )
                        . "\\\"},\\n\";\n";
                }
                $counter2++;
            }
        }

        $output .= "print \"]}\\n\";\n";

        open( JSON, ">" . $site->{"file"} ) or die "can't open " . $site->{"file"};
        print JSON $output;
        close( JSON );
        system( "chmod 755 " . $site->{"file"} );

    }

    sleep( 5 );
}

__END__

=head1 SEE ALSO

L<CGI>, L<XML::LibXML>, L<Date::Manip>, L<English>, L<perfSONAR_PS::Client::MA>,
L<perfSONAR_PS::Common>, L<perfSONAR_PS::Utils::ParameterValidation>

To join the 'perfSONAR-PS' mailing list, please visit:

  https://mail.internet2.edu/wws/info/i2-perfsonar

The perfSONAR-PS subversion repository is located at:

  https://svn.internet2.edu/svn/perfSONAR-PS

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

