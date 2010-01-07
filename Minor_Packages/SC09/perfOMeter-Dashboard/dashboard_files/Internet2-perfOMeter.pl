#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

Internet2-perfOMeter.pl - Helper script to automatically generate JSON data for use in a dashboard application.

=head1 DESCRIPTION

Contact an SNMP MA for several interfaces.  Generate JSON data files for use in a live dashboard application.  

=cut

use XML::LibXML;
use Date::Manip;
use English qw( -no_match_vars );

#use FindBin qw($RealBin);
#my $basedir = "$RealBin/";
#use lib "$RealBin/../lib";

#use lib "/opt/perfsonar_ps/perfAdmin/lib";
#use lib "/home/zurawski/RELEASE_3.1/perfSONAR_PS-perfAdmin/lib";
use lib "/home/zurawski/perfOMeter/Shared/lib";

use perfSONAR_PS::Client::MA;
use perfSONAR_PS::Common qw( extract find );
use perfSONAR_PS::Utils::ParameterValidation;

my $DEBUG  = 0;
my $DEBUG2 = 0;

my @list = ();

# NEWY/WASH
push @list,
    {
    file       => "wash_newy.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.newy32aoa.net.internet2.edu",
            ifName    => "xe-1/0/0.0",
            direction => "in"
        },
        {
            hostName  => "rtr.newy32aoa.net.internet2.edu",
            ifName    => "xe-2/0/0.0",
            direction => "in"
        }
    ],
    resolution => "5",
    length     => "40"
    };
push @list,
    {
    file       => "newy_wash.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.newy32aoa.net.internet2.edu",
            ifName    => "xe-1/0/0.0",
            direction => "out"
        },
        {
            hostName  => "rtr.newy32aoa.net.internet2.edu",
            ifName    => "xe-2/0/0.0",
            direction => "out"
        }
    ],
    resolution => "5",
    length     => "40"
    };

# NEWY/CHIC
push @list,
    {
    file       => "chic_newy.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.newy32aoa.net.internet2.edu",
            ifName    => "xe-0/0/0.0",
            direction => "in"
        }
    ],
    resolution => "5",
    length     => "40"
    };
push @list,
    {
    file       => "newy_chic.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.newy32aoa.net.internet2.edu",
            ifName    => "xe-0/0/0.0",
            direction => "out"
        }
    ],
    resolution => "5",
    length     => "40"
    };

# WASH/ATLA
push @list,
    {
    file       => "atla_wash.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.wash.net.internet2.edu",
            ifName    => "xe-1/0/0.0",
            direction => "in"
        },
        {
            hostName  => "rtr.wash.net.internet2.edu",
            ifName    => "xe-2/0/0.0",
            direction => "in"
        }
    ],
    resolution => "5",
    length     => "40"
    };
push @list,
    {
    file       => "wash_atla.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.wash.net.internet2.edu",
            ifName    => "xe-1/0/0.0",
            direction => "out"
        },
        {
            hostName  => "rtr.wash.net.internet2.edu",
            ifName    => "xe-2/0/0.0",
            direction => "out"
        }
    ],
    resolution => "5",
    length     => "40"
    };

# WASH/CHIC
push @list,
    {
    file       => "chic_wash.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.wash.net.internet2.edu",
            ifName    => "xe-0/0/0.0",
            direction => "in"
        }
    ],
    resolution => "5",
    length     => "40"
    };
push @list,
    {
    file       => "wash_chic.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.wash.net.internet2.edu",
            ifName    => "xe-0/0/0.0",
            direction => "out"
        }
    ],
    resolution => "5",
    length     => "40"
    };

# ATLA/CHIC
push @list,
    {
    file       => "chic_atla.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.atla.net.internet2.edu",
            ifName    => "xe-0/0/0.0",
            direction => "in"
        }
    ],
    resolution => "5",
    length     => "40"
    };
push @list,
    {
    file       => "atla_chic.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.atla.net.internet2.edu",
            ifName    => "xe-0/0/0.0",
            direction => "out"
        }
    ],
    resolution => "5",
    length     => "40"
    };

# ATLA/HOUS
push @list,
    {
    file       => "hous_atla.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.atla.net.internet2.edu",
            ifName    => "xe-1/0/0.0",
            direction => "in"
        }
    ],
    resolution => "5",
    length     => "40"
    };
push @list,
    {
    file       => "atla_hous.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.atla.net.internet2.edu",
            ifName    => "xe-1/0/0.0",
            direction => "out"
        }
    ],
    resolution => "5",
    length     => "40"
    };

# CHIC/KANS
push @list,
    {
    file       => "kans_chic.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.chic.net.internet2.edu",
            ifName    => "so-1/2/0.0",
            direction => "in"
        },
        {
            hostName  => "rtr.chic.net.internet2.edu",
            ifName    => "so-5/0/0.0",
            direction => "in"
        }
    ],
    resolution => "5",
    length     => "40"
    };
push @list,
    {
    file       => "chic_kans.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.chic.net.internet2.edu",
            ifName    => "so-1/2/0.0",
            direction => "out"
        },
        {
            hostName  => "rtr.chic.net.internet2.edu",
            ifName    => "so-5/0/0.0",
            direction => "out"
        }
    ],
    resolution => "5",
    length     => "40"
    };

# KANS/SALT
push @list,
    {
    file       => "salt_kans.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.kans.net.internet2.edu",
            ifName    => "so-4/2/0.0",
            direction => "in"
        },
        {
            hostName  => "rtr.kans.net.internet2.edu",
            ifName    => "xe-4/1/0.0",
            direction => "in"
        }
    ],
    resolution => "5",
    length     => "40"
    };
push @list,
    {
    file       => "kans_salt.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.kans.net.internet2.edu",
            ifName    => "so-4/2/0.0",
            direction => "out"
        },
        {
            hostName  => "rtr.kans.net.internet2.edu",
            ifName    => "xe-4/1/0.0",
            direction => "out"
        }
    ],
    resolution => "5",
    length     => "40"
    };

# KANS/HOUS
push @list,
    {
    file       => "hous_kans.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.kans.net.internet2.edu",
            ifName    => "so-5/0/0.0",
            direction => "in"
        },
        {
            hostName  => "rtr.kans.net.internet2.edu",
            ifName    => "so-4/0/0.0",
            direction => "in"
        }
    ],
    resolution => "5",
    length     => "40"
    };
push @list,
    {
    file       => "kans_hous.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.kans.net.internet2.edu",
            ifName    => "so-5/0/0.0",
            direction => "out"
        },
        {
            hostName  => "rtr.kans.net.internet2.edu",
            ifName    => "so-4/0/0.0",
            direction => "out"
        }
    ],
    resolution => "5",
    length     => "40"
    };

# HOUS/LOSA
push @list,
    {
    file       => "losa_hous.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.hous.net.internet2.edu",
            ifName    => "so-0/0/0.0",
            direction => "in"
        },
        {
            hostName  => "rtr.hous.net.internet2.edu",
            ifName    => "so-3/2/0.0",
            direction => "in"
        }
    ],
    resolution => "5",
    length     => "40"
    };
push @list,
    {
    file       => "hous_losa.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.hous.net.internet2.edu",
            ifName    => "so-0/0/0.0",
            direction => "out"
        },
        {
            hostName  => "rtr.hous.net.internet2.edu",
            ifName    => "so-3/2/0.0",
            direction => "out"
        }
    ],
    resolution => "5",
    length     => "40"
    };

# SALT/SEAT
push @list,
    {
    file       => "seat_salt.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.salt.net.internet2.edu",
            ifName    => "so-3/0/0.0",
            direction => "in"
        }
    ],
    resolution => "5",
    length     => "40"
    };
push @list,
    {
    file       => "salt_seat.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.salt.net.internet2.edu",
            ifName    => "so-3/0/0.0",
            direction => "out"
        }
    ],
    resolution => "5",
    length     => "40"
    };

# SALT/LOSA
push @list,
    {
    file       => "losa_salt.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.salt.net.internet2.edu",
            ifName    => "so-3/1/0.0",
            direction => "in"
        }
    ],
    resolution => "5",
    length     => "40"
    };
push @list,
    {
    file       => "salt_losa.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.salt.net.internet2.edu",
            ifName    => "so-3/1/0.0",
            direction => "out"
        }
    ],
    resolution => "5",
    length     => "40"
    };

# LOSA/SEAT
push @list,
    {
    file       => "seat_losa.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.losa.net.internet2.edu",
            ifName    => "so-0/1/0.0",
            direction => "in"
        }
    ],
    resolution => "5",
    length     => "40"
    };
push @list,
    {
    file       => "losa_seat.json",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    interfaces => [
        {
            hostName  => "rtr.losa.net.internet2.edu",
            ifName    => "so-0/1/0.0",
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

                print $time . " - " . ( int( $value ) * 8 ) / 1048576 . "\n" if $DEBUG and $value and $time and $value ne "nan";
                next unless $time and $value;
                $value = 0 if $value eq "nan";
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
            my $v = ( int( $store{$time} ) * 8 ) / 1048576 if $store{$time};
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
}

