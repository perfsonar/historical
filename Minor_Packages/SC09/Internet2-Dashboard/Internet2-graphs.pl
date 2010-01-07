#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

Internet2-graphs.pl - Helper script to automatically generate JSON data for use in a dashboard application.

=head1 DESCRIPTION

Contact an SNMP MA for several interfaces.  Generate JSON data files (in this case CGIs that return JSON data files - this defeats browser and library caching) for use in a live dashboard application.  

=cut

use CGI;
use XML::LibXML;
use Date::Manip;
use English qw( -no_match_vars );

#use FindBin qw($RealBin);
#my $basedir = "$RealBin/";
#use lib "$RealBin/../lib";

use lib "/opt/perfsonar_ps/perfAdmin/lib";

#use lib "/home/zurawski/RELEASE_3.1/perfSONAR_PS-perfAdmin/lib";

use perfSONAR_PS::Client::MA;
use perfSONAR_PS::Common qw( extract find );
use perfSONAR_PS::Utils::ParameterValidation;

my @list = ();
push @list,
    {
    file       => "atla.cgi",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    hostName   => "rtr.atla.net.internet2.edu",
    ifName     => "xe-9/2/0",
    length     => 900,
    resolution => 1
    };
push @list,
    {
    file       => "chic.cgi",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    hostName   => "rtr.chic.net.internet2.edu",
    ifName     => "ge-0/1/0.11",
    length     => 900,
    resolution => 1
    };
push @list,
    {
    file       => "hous.cgi",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    hostName   => "rtr.hous.net.internet2.edu",
    ifName     => "xe-2/0/0.11",
    length     => 900,
    resolution => 1
    };
push @list,
    {
    file       => "kans.cgi",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    hostName   => "rtr.kans.net.internet2.edu",
    ifName     => "ge-0/1/0.11",
    length     => 900,
    resolution => 1
    };
push @list,
    {
    file       => "losa.cgi",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    hostName   => "rtr.losa.net.internet2.edu",
    ifName     => "ge-4/0/0.11",
    length     => 900,
    resolution => 1
    };
push @list,
    {
    file       => "newy.cgi",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    hostName   => "rtr.newy32aoa.net.internet2.edu",
    ifName     => "xe-9/2/0",
    length     => 900,
    resolution => 1
    };
push @list,
    {
    file       => "salt.cgi",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    hostName   => "rtr.salt.net.internet2.edu",
    ifName     => "ge-0/2/0.11",
    length     => 900,
    resolution => 1
    };
push @list,
    {
    file       => "seat.cgi",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    hostName   => "rtr.seat.net.internet2.edu",
    ifName     => "ge-3/2/0.11",
    length     => 900,
    resolution => 1
    };
push @list,
    {
    file       => "sox.cgi",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    hostName   => "rtr.atla.net.internet2.edu",
    ifName     => "xe-2/2/0.195",
    length     => 900,
    resolution => 1
    };
push @list,
    {
    file       => "wash.cgi",
    url        => "http://rrdma.net.internet2.edu:8080/perfSONAR_PS/services/snmpMA",
    hostName   => "rtr.wash.net.internet2.edu",
    ifName     => "xe-9/2/0",
    length     => 900,
    resolution => 1
    };

while ( 1 ) {

    foreach my $site ( @list ) {

        my $output = q{};
        $output = "#!/usr/bin/perl\n\n";
        $output .= "print \"Content-type: application/json\\n\\n\";\n\n";

        my $url        = $site->{"url"};
        my $ifAddress  = $site->{"ifAddress"};
        my $hostName   = $site->{"hostName"};
        my $ifName     = $site->{"ifName"};
        my $length     = $site->{"length"};
        my $resolution = $site->{"resolution"};

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

        my $doc1 = q{};
        eval { $doc1 = $parser->parse_string( $result->{"data"}->[0] ); };
        if ( $EVAL_ERROR ) {
            next;
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
            next;
        }
        my $datum2 = find( $doc2->getDocumentElement, "./*[local-name()='datum']", 0 );

        my $counter = 0;
        my %store   = ();
        my $inUnit  = q{};
        my $outUnit = q{};
        foreach my $dt ( $datum1->get_nodelist ) {
            $counter++;
        }
        foreach my $dt ( $datum1->get_nodelist ) {
            $store{ $dt->getAttribute( "timeValue" ) }{"in"} = eval( $dt->getAttribute( "value" ) );
            $inUnit = $dt->getAttribute( "valueUnits" ) unless $inUnit;
        }
        foreach my $dt ( $datum2->get_nodelist ) {
            $store{ $dt->getAttribute( "timeValue" ) }{"out"} = eval( $dt->getAttribute( "value" ) );
            $outUnit = $dt->getAttribute( "valueUnits" ) unless $outUnit;
        }

        my $mul = 1;
        my $div = 1000000;
        if ( $inUnit and $outUnit and ( $inUnit eq $outUnit ) ) {
            if ( $inUnit =~ m/.*Bps$/ ) {
                $mul = 8;
            }
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

    sleep( 10 );
}

__END__

=head1 SEE ALSO

L<CGI>, L<XML::LibXML>, L<Date::Manip>, L<English>, L<perfSONAR_PS::Client::MA>, L<perfSONAR_PS::Common>, L<perfSONAR_PS::Utils::ParameterValidation>

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
