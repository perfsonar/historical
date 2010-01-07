#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

SC09-perfOMeter.pl - Generates JSON data for a dashboard application.

=head1 DESCRIPTION

Given some SNMP MA interface information, extract the values and create JSON
data suitable for use in a dashboard application. 

=cut

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

my $DEBUG  = 0;
my $DEBUG2 = 0;

my @list = ();

# UDel
# dnoc-rtr-1739 Eth1/26 (using Internet2 connection)
# dnoc-rtr-2488 xe-3/0/7 (using Vanderbilt connection)
push @list,
    {
    file       => "bwc-udel_wan.json",
    url        => "http://monitor.sc09.org:9990/perfSONAR_PS/services/SNMPMA",
    interfaces => [
        {
            hostName  => "dnoc-rtr-1739.sc09.org",
            ifName    => "Ethernet1/26",
            direction => "in"
        },
        {
            hostName  => "dnoc-rtr-2488.sc09.org",
            ifName    => "xe-3/0/7",
            direction => "in"
        }
    ],
    resolution => "5",
    length     => "40"
    };
push @list,
    {
    file       => "wan_bwc-udel.json",
    url        => "http://monitor.sc09.org:9990/perfSONAR_PS/services/SNMPMA",
    interfaces => [
        {
            hostName  => "dnoc-rtr-1739.sc09.org",
            ifName    => "Ethernet1/26",
            direction => "out"
        },
        {
            hostName  => "dnoc-rtr-2488.sc09.org",
            ifName    => "xe-3/0/7",
            direction => "out"
        }
    ],
    resolution => "5",
    length     => "40"
    };
push @list,
    {
    file       => "bwc-internet2_wan.json",
    url        => "http://monitor.sc09.org:9990/perfSONAR_PS/services/SNMPMA",
    interfaces => [
        {
            hostName  => "dnoc-rtr-1739.sc09.org",
            ifName    => "Ethernet1/26",
            direction => "in"
        }
    ],
    resolution => "5",
    length     => "40"
    };
push @list,
    {
    file       => "bwc-vandy_wan.json",
    url        => "http://monitor.sc09.org:9990/perfSONAR_PS/services/SNMPMA",
    interfaces => [
        {
            hostName  => "dnoc-rtr-2488.sc09.org",
            ifName    => "xe-3/0/7",
            direction => "in"
        }
    ],
    resolution => "5",
    length     => "40"
    };
push @list,
    {
    file       => "wan_bwc-internet2.json",
    url        => "http://monitor.sc09.org:9990/perfSONAR_PS/services/SNMPMA",
    interfaces => [
        {
            hostName  => "dnoc-rtr-1739.sc09.org",
            ifName    => "Ethernet1/26",
            direction => "out"
        }
    ],
    resolution => "5",
    length     => "40"
    };
push @list,
    {
    file       => "wan_bwc-vandy.json",
    url        => "http://monitor.sc09.org:9990/perfSONAR_PS/services/SNMPMA",
    interfaces => [
        {
            hostName  => "dnoc-rtr-2488.sc09.org",
            ifName    => "xe-3/0/7",
            direction => "out"
        }
    ],
    resolution => "5",
    length     => "40"
    };

# UIC
# dnoc-rtr-1739 Eth1/17
# dnoc-rtr-1739 Eth1/18

push @list,
    {
    file       => "bwc-uic_wan.json",
    url        => "http://monitor.sc09.org:9990/perfSONAR_PS/services/SNMPMA",
    interfaces => [
        {
            hostName  => "dnoc-rtr-1739.sc09.org",
            ifName    => "Ethernet1/17",
            direction => "in"
        },
        {
            hostName  => "dnoc-rtr-1739.sc09.org",
            ifName    => "Ethernet1/18",
            direction => "in"
        }
    ],
    resolution => "5",
    length     => "40"
    };
push @list,
    {
    file       => "wan_bwc-uic.json",
    url        => "http://monitor.sc09.org:9990/perfSONAR_PS/services/SNMPMA",
    interfaces => [
        {
            hostName  => "dnoc-rtr-1739.sc09.org",
            ifName    => "Ethernet1/17",
            direction => "out"
        },
        {
            hostName  => "dnoc-rtr-1739.sc09.org",
            ifName    => "Ethernet1/18",
            direction => "out"
        }
    ],
    resolution => "5",
    length     => "40"
    };

# ANL
# dnoc-rtr-2488 xe-3/0/3 (using Utah connections)
# dnoc-rtr-2488 xe-3/0/4
push @list,
    {
    file       => "bwc-anl_wan.json",
    url        => "http://monitor.sc09.org:9990/perfSONAR_PS/services/SNMPMA",
    interfaces => [
        {
            hostName  => "dnoc-rtr-2488.sc09.org",
            ifName    => "xe-3/0/3",
            direction => "in"
        },
        {
            hostName  => "dnoc-rtr-2488.sc09.org",
            ifName    => "xe-3/0/4",
            direction => "in"
        }
    ],
    resolution => "5",
    length     => "40"
    };
push @list,
    {
    file       => "wan_bwc-anl.json",
    url        => "http://monitor.sc09.org:9990/perfSONAR_PS/services/SNMPMA",
    interfaces => [
        {
            hostName  => "dnoc-rtr-2488.sc09.org",
            ifName    => "xe-3/0/3",
            direction => "out"
        },
        {
            hostName  => "dnoc-rtr-2488.sc09.org",
            ifName    => "xe-3/0/4",
            direction => "out"
        }
    ],
    resolution => "5",
    length     => "40"
    };

# Caltech

push @list,
    {
    file       => "bwc-caltech_wan.json",
    url        => "http://monitor.sc09.org:9990/perfSONAR_PS/services/SNMPMA",
    interfaces => [
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet1/1",
            direction => "in"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet1/2",
            direction => "in"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet2/10",
            direction => "in"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet2/2",
            direction => "in"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet2/9",
            direction => "in"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet1/10",
            direction => "in"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet3/2",
            direction => "in"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet1/9",
            direction => "in"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet2/1",
            direction => "in"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet4/1",
            direction => "in"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet4/2",
            direction => "in"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet4/9",
            direction => "in"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet4/18",
            direction => "in"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet3/10",
            direction => "in"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet4/10",
            direction => "in"
        }
    ],
    resolution => "5",
    length     => "40"
    };
push @list,
    {
    file       => "wan_bwc-caltech.json",
    url        => "http://monitor.sc09.org:9990/perfSONAR_PS/services/SNMPMA",
    interfaces => [
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet1/1",
            direction => "out"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet1/2",
            direction => "out"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet2/10",
            direction => "out"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet2/2",
            direction => "out"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet2/9",
            direction => "out"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet1/10",
            direction => "out"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet3/2",
            direction => "out"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet1/9",
            direction => "out"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet2/1",
            direction => "out"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet4/1",
            direction => "out"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet4/2",
            direction => "out"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet4/9",
            direction => "out"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet4/18",
            direction => "out"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet3/10",
            direction => "out"
        },
        {
            hostName  => "2135J-scinet.sc09.org",
            ifName    => "Ethernet4/10",
            direction => "out"
        }
    ],
    resolution => "5",
    length     => "40"
    };

# Tokyo
# dnoc-rtr-1050 ethernet 4/4
push @list,
    {
    file       => "bwc-tokyo_wan.json",
    url        => "http://monitor.sc09.org:9990/perfSONAR_PS/services/SNMPMA",
    interfaces => [
        {
            hostName  => "dnoc-rtr-1050.sc09.org",
            ifName    => "10GigabitEthernet4/4",
            direction => "in"
        }
    ],
    resolution => "5",
    length     => "40"
    };
push @list,
    {
    file       => "wan_bwc-tokyo.json",
    url        => "http://monitor.sc09.org:9990/perfSONAR_PS/services/SNMPMA",
    interfaces => [
        {
            hostName  => "dnoc-rtr-1050.sc09.org",
            ifName    => "10GigabitEthernet4/4",
            direction => "out"
        }
    ],
    resolution => "5",
    length     => "40"
    };

while ( 1 ) {
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( time );
    print "Start:\t" . sprintf( "%02d", $hour ) . ":" . sprintf( "%02d", $min ) . ":" . sprintf( "%02d", $sec ) . "\n" if $DEBUG2;

    foreach my $site ( @list ) {
        my $output = q{};

        print $site->{"file"} . "\n" if $DEBUG;

        my $url        = $site->{"url"};
        my $length     = $site->{"length"};
        my $resolution = $site->{"resolution"};

        my %store = ();
        foreach my $interface ( @{ $site->{"interfaces"} } ) {

            my $ifAddress = $interface->{"ifAddress"};
            my $hostName  = $interface->{"hostName"};
            my $ifName    = $interface->{"ifName"};
            my $direction = $interface->{"direction"};

            my $subject = "    <netutil:subject xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\" id=\"subject.1\">\n";
            $subject .= "      <nmwgt:interface xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";
            $subject .= "        <nmwgt:ifAddress>" . $ifAddress . "</nmwgt:ifAddress>\n" if $ifAddress;
            $subject .= "        <nmwgt:hostName>" . $hostName . "</nmwgt:hostName>\n" if $hostName;
            $subject .= "        <nmwgt:ifName>" . $ifName . "</nmwgt:ifName>\n" if $ifName;
            $subject .= "        <nmwgt:direction>" . $direction . "</nmwgt:direction>\n" if $direction;
            $subject .= "      </nmwgt:interface>\n";
            $subject .= "    </netutil:subject>\n";

            my $ma = new perfSONAR_PS::Client::MA( { instance => $url } );

            my @eventTypes = ( "http://ggf.org/ns/nmwg/characteristic/utilization/2.0" );
            my $parser     = XML::LibXML->new();
            my $sec        = time;
            $sec -= ( $sec % $resolution );

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

            my $doc = q{};
            eval { $doc = $parser->parse_string( $result->{"data"}->[0] ); };
            if ( $EVAL_ERROR ) {
                next;
            }
            my $datum = find( $doc->getDocumentElement, "./*[local-name()='datum']", 0 );
            foreach my $dt ( $datum->get_nodelist ) {
                my $time  = $dt->getAttribute( "timeValue" );
                my $value = $dt->getAttribute( "value" );

                #                print $time . " - " . ( int( $value ) * 8 ) / 1048576 . "\n" if $DEBUG and $value and $time and $value ne "nan";
                print $time . " - " . int( $value ) / 1048576 . "\n" if $DEBUG and $value and $time and $value ne "nan";
                next unless $time and $value;
                $value = 0 if $value eq "nan";

                #                if ( $value and ( $value > 10737418240 ) ) {
                #                    $value = 10737418240;
                #                }

                if ( exists $store{$time} and $store{$time} ) {
                    $store{$time} += eval( $value );
                }
                else {
                    $store{$time} = eval( $value );
                }
            }
            print "\n" if $DEBUG;
        }
        print "\n\n" if $DEBUG;

        $output .= "\{\"servdata\"\: \{\n    \"data\"\: \[\n";
        foreach my $time ( sort keys %store ) {
            my $t = int( $time );

            # convert to mbps
            #            my $v = ( int( $store{ $time } ) * 8 ) / 1048576 if $store{ $time };
            my $v = int( $store{$time} ) / 1048576 if $store{$time};

            next unless $v;
            next if ( $v eq 'nan' );
            $output .= '        [' . $t . "," . $v . '],' . "\n";
        }
        $output .= "\n      \]\n    \}\n\}";

        open( JSON, ">" . $site->{"file"} ) or die "can't open " . $site->{"file"};
        print JSON $output;
        close( JSON );
    }

    ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime( time );
    print "End:\t" . sprintf( "%02d", $hour ) . ":" . sprintf( "%02d", $min ) . ":" . sprintf( "%02d", $sec ) . "\n\n" if $DEBUG2;
    sleep( 5 );
}

__END__

=head1 SEE ALSO

L<XML::LibXML>, L<Date::Manip>, L<English>, L<perfSONAR_PS::Client::MA>,
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

