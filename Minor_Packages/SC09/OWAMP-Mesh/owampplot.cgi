#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

owampplot.cgi - Graph displaying recent OWAMP data from a pSB database.

=head1 DESCRIPTION

Read the OWAMP portion of the pSB database and graph some length of time.  

=cut

use DBI;
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use XML::LibXML;
use Date::Manip;
use Socket;
use POSIX;
use Time::Local 'timelocal_nocheck';
use English qw( -no_match_vars );

use lib "/opt/perfsonar_ps/perfsonarbuoy_ma/lib";

use OWP;
use OWP::Utils;
use perfSONAR_PS::Utils::ParameterValidation;

my %amidefaults;

BEGIN {
    %amidefaults = (
        CONFDIR => "/opt/perfsonar_ps/perfsonarbuoy_ma/etc",
        LIBDIR  => "/opt/perfsonar_ps/perfsonarbuoy_ma/lib",
    );
}

my $cgi  = CGI->new();
my $send = q{};
if ( $cgi->param( 'send' ) ) {
    $send = $cgi->param( 'send' );
}
else {
    croak "Must Supply 'send' parameter, aborting.\n";
}

my $recv = q{};
if ( $cgi->param( 'recv' ) ) {
    $recv = $cgi->param( 'recv' );
}
else {
    croak "Must Supply 'recv' parameter, aborting.\n";
}

my $type = q{};
if ( $cgi->param( 'type' ) ) {
    $type = $cgi->param( 'type' );
}

my ( $sec, $frac ) = Time::HiRes::gettimeofday;
my $startTime;
my $endTime;
if ( $cgi->param( 'length' ) ) {
    $startTime = $sec - $cgi->param( 'length' );
    $endTime   = $sec;
}
elsif ( $cgi->param( 'smon' ) or $cgi->param( 'sday' ) or $cgi->param( 'syear' ) or $cgi->param( 'emon' ) or $cgi->param( 'eday' ) or $cgi->param( 'eyear' ) ) {
    if ( $cgi->param( 'smon' ) and $cgi->param( 'sday' ) and $cgi->param( 'syear' ) and $cgi->param( 'emon' ) and $cgi->param( 'eday' ) and $cgi->param( 'eyear' ) ) {
        $startTime = timelocal_nocheck 0, 0, ( $cgi->param( 'shour' ) ), ( $cgi->param( 'sday' ) ), ( $cgi->param( 'smon' ) - 1 ), ( $cgi->param( 'syear' ) - 1900 );
        $endTime   = timelocal_nocheck 0, 0, ( $cgi->param( 'ehour' ) ), ( $cgi->param( 'eday' ) ), ( $cgi->param( 'emon' ) - 1 ), ( $cgi->param( 'eyear' ) - 1900 );
    }
    else {
        print "<html><head><title>perfSONAR-PS perfAdmin Delay Graph</title></head>";
        print "<body><h2 align=\"center\">Graph error; Date not correctly entered.</h2></body></html>";
        exit( 1 );
    }
}
else {
    $startTime = $sec - 7200;
    $endTime   = $sec;
}

my ( $e_sec, $e_min, $e_hour, $e_mday, $e_mon, $e_year ) = gmtime( $endTime );
my ( $s_sec, $s_min, $s_hour, $s_mday, $s_mon, $s_year ) = gmtime( $startTime );

print "Content-type: text/html\n\n";

my $conf = new OWP::Conf( %amidefaults );

my $dbhost = $conf->must_get_val( ATTR => 'CentralDBHost' );
my $dbtype = $conf->must_get_val( ATTR => 'CentralDBType' );
my $dbname = $conf->must_get_val( ATTR => 'OWPCentralDBName' );
my $dbuser = $conf->must_get_val( ATTR => 'CGIDBUser' );
my $dbpass = $conf->get_val( ATTR      => 'CGIDBPass' );

my $dbsource = $dbtype . ":" . $dbname . ":" . $dbhost;
my $dbh      = DBI->connect(
    $dbsource,
    $dbuser, $dbpass,
    {
        RaiseError => 0,
        PrintError => 1
    }
) || croak "Couldn't connect to database";

#
#  Sanity check the DB to be sure we have the proper date(s) stored
#
my $sql = "select * from DATES where year=" . ( $s_year + 1900 ) . " and month=" . ( $s_mon + 1 ) . " and day=" . $s_mday;
my $s_date_ref = $dbh->selectall_arrayref( $sql );

$sql = "select * from DATES where year=" . ( $e_year + 1900 ) . " and month=" . ( $e_mon + 1 ) . " and day=" . $e_mday;
my $e_date_ref = $dbh->selectall_arrayref( $sql );

unless ( exists $e_date_ref->[0] ) {
    push @{ $e_date_ref->[0] }, $s_date_ref->[0][0];
    push @{ $e_date_ref->[0] }, $s_date_ref->[0][1];
}

my $flag       = 1;
my @cursor     = ( $s_date_ref->[0][0], $s_date_ref->[0][1], $s_date_ref->[0][2] );
my @dates_list = ();
while ( $flag == 1 ) {
    push @dates_list, [ $cursor[0], sprintf( "%02d", $cursor[1] ), sprintf( "%02d", $cursor[2] ) ];
    $flag = 0 if $cursor[0] == $e_date_ref->[0][0] and $cursor[1] == $e_date_ref->[0][1] and $cursor[2] == $e_date_ref->[0][2];
    $cursor[2]++;

    if ( $cursor[1] == 4 or $cursor[1] == 6 or $cursor[1] == 9 or $cursor[1] == 11 ) {
        if ( $cursor[2] == 30 ) {
            $cursor[1]++;
            $cursor[2] = 1;
        }
    }
    elsif ( $cursor[1] == 1 or $cursor[1] == 3 or $cursor[1] == 5 or $cursor[1] == 7 or $cursor[1] == 8 or $cursor[1] == 10 or $cursor[1] == 12 ) {
        if ( $cursor[2] == 31 ) {
            $cursor[1]++;
            $cursor[2] = 1;
        }
    }
    elsif ( $cursor[1] == 2 ) {
        if ( 0 == ( $cursor[0] % 4 ) and 0 != ( $cursor[0] % 100 ) or 0 == ( $cursor[0] % 400 ) ) {
            if ( $cursor[2] == 29 ) {
                $cursor[1]++;
                $cursor[2] = 1;
            }
        }
        else {
            if ( $cursor[2] == 28 ) {
                $cursor[1]++;
                $cursor[2] = 1;
            }
        }
    }

    if ( $cursor[1] == 13 ) {
        $cursor[0]++;
        $cursor[1] = 1;
    }
}

use Data::Dumper;
print STDERR Dumper( @dates_list ) . "\n";

$sql = q{};
foreach my $d ( @dates_list ) {
    $sql .= " union " if $sql;
    $sql .= " select node_id, node_name, longname from " . $d->[0] . $d->[1] . $d->[2] . "_NODES ";
}

my $ref = $dbh->selectall_arrayref( $sql );

my %map  = ();
my %name = ();
foreach my $r ( @{$ref} ) {
    push @{ $map{ $r->[1] } }, $r->[0] if $r->[0] and $r->[1];
    $name{ $r->[1] } = $r->[2] if $r->[2] and $r->[1];
}

#my %r_map = reverse %map;

print STDERR Dumper( %map ) . "\n";

my %store   = ();
my $counter = 0;
my @flags   = ( 0, 0, 0, 0, 0, 0 );
if ( $s_year == $e_year ) {

    # do one select statement

    $sql = q{};
    foreach my $d ( @dates_list ) {
        $sql .= " union " if $sql;
        $sql .= " select * from " . $d->[0] . $d->[1] . $d->[2] . "_DATA where ";

        my $sc   = 0;
        my $ssql = " ( ";
        foreach my $s ( @{ $map{$send} } ) {
            $ssql .= " or " if $sc;
            $ssql .= " send_id=\"" . $s . "\" ";
            $sc++;
        }

        my $rc   = 0;
        my $rsql = " ( ";
        foreach my $r ( @{ $map{$recv} } ) {
            $rsql .= " or " if $rc;
            $rsql .= " recv_id=\"" . $r . "\" ";
            $rc++;
        }
        $sql .= $ssql . " ) and " . $rsql . " ) and etimestamp > '" . time2owptime( $startTime ) . "' and etimestamp < '" . time2owptime( $endTime ) . "' ";
    }
    $sql .= ";" if $sql;

    print STDERR $sql . "\n";

    $ref = $dbh->selectall_arrayref( $sql );

    foreach my $r ( @{$ref} ) {
        my $secs = owptime2time( $r->[6] );
        my $min  = $r->[9];
        my $max  = $r->[10];
        my $sent = $r->[13];
        my $lost = $r->[14];
        my $dups = $r->[15];
        $store{$secs}{"src"}{"min"} = ( $min ) if $min;
        $store{$secs}{"src"}{"max"} = ( $max ) if $max;
        $flags[0] = 1 if $min or $max;
        $store{$secs}{"src"}{"sent"} = ( $sent ) if $sent;
        $store{$secs}{"src"}{"lost"} = ( $lost ) if $lost;
        $flags[1]                    = 1         if $lost;
        $store{$secs}{"src"}{"dups"} = ( $dups ) if $dups;
        $flags[2]                    = 1         if $dups;
    }

    $sql = q{};
    foreach my $d ( @dates_list ) {
        $sql .= " union " if $sql;
        $sql .= " select * from " . $d->[0] . $d->[1] . $d->[2] . "_DATA where ";

        my $sc   = 0;
        my $ssql = " ( ";
        foreach my $s ( @{ $map{$send} } ) {
            $ssql .= " or " if $sc;
            $ssql .= " recv_id=\"" . $s . "\" ";
            $sc++;
        }

        my $rc   = 0;
        my $rsql = " ( ";
        foreach my $r ( @{ $map{$recv} } ) {
            $rsql .= " or " if $rc;
            $rsql .= " send_id=\"" . $r . "\" ";
            $rc++;
        }
        $sql .= $ssql . " ) and " . $rsql . " ) and etimestamp > '" . time2owptime( $startTime ) . "' and etimestamp < '" . time2owptime( $endTime ) . "' ";
    }
    $sql .= ";" if $sql;
    $ref = $dbh->selectall_arrayref( $sql );

    print STDERR $sql . "\n";

    foreach my $r ( @{$ref} ) {
        my $secs = owptime2time( $r->[6] );
        my $min  = $r->[9];
        my $max  = $r->[10];
        my $sent = $r->[13];
        my $lost = $r->[14];
        my $dups = $r->[15];
        $store{$secs}{"dest"}{"min"} = ( $min ) if $min;
        $store{$secs}{"dest"}{"max"} = ( $max ) if $max;
        $flags[3] = 1 if $min or $max;
        $store{$secs}{"dest"}{"sent"} = ( $sent ) if $sent;
        $store{$secs}{"dest"}{"lost"} = ( $lost ) if $lost;
        $flags[4]                     = 1         if $lost;
        $store{$secs}{"dest"}{"dups"} = ( $dups ) if $dups;
        $flags[5]                     = 1         if $dups;
    }

    foreach my $time ( keys %store ) {
        $counter++;
    }
}
else {

    # do two select statements ...
}

print "<html>\n";
print "  <head>\n";
print "    <title>perfSONAR-PS perfAdmin Delay Graph</title>\n";

print STDERR Dumper( %store ) . "\n";

use Data::Dumper;
print STDERR Dumper( @flags ) . "\n";

if ( $flags[0] or $flags[3] ) {
    if ( scalar keys %store > 0 ) {
        my $title = q{};
        if ( $cgi->param( 'src' ) and $cgi->param( 'dst' ) ) {

            if ( $cgi->param( 'shost' ) and $cgi->param( 'dhost' ) ) {
                $title = "Source: " . $cgi->param( 'shost' );
                $title .= " (" . $cgi->param( 'src' ) . ") ";
                $title .= " -- Destination: " . $cgi->param( 'dhost' );
                $title .= " (" . $cgi->param( 'dst' ) . ") ";
            }
            else {
                my $display = $cgi->param( 'src' );
                my $iaddr   = Socket::inet_aton( $display );
                my $shost   = gethostbyaddr( $iaddr, Socket::AF_INET );
                $display = $cgi->param( 'dst' );
                $iaddr   = Socket::inet_aton( $display );
                my $dhost = gethostbyaddr( $iaddr, Socket::AF_INET );
                $title = "Source: " . $shost;
                $title .= " (" . $cgi->param( 'src' ) . ") " if $shost;
                $title .= " -- Destination: " . $dhost;
                $title .= " (" . $cgi->param( 'dst' ) . ") " if $dhost;
            }
        }
        else {
            $title = "Observed Latency";
        }

        my $posCounter = 1;
        my @pos        = ( "src-min", "src-max", "src-loss", "src-loss2", "src-dups", "src-dups2", "dst-min", "dst-max", "dst-loss", "dst-loss2", "dst-dups", "dst-dups2" );
        my %posMap     = ();

        print "    <script type=\"text/javascript\" src=\"http://www.google.com/jsapi\"></script>\n";
        print "    <script type=\"text/javascript\">\n";
        print "      google.load(\"visualization\", \"1\", {packages:[\"annotatedtimeline\"]});\n";
        print "      google.setOnLoadCallback(drawChart);\n";
        print "      function drawChart() {\n";
        print "        var data = new google.visualization.DataTable();\n";

        print "        data.addColumn('datetime', 'Time');\n";

        if ( $flags[0] ) {
            print "        data.addColumn('number', '[Src to Dst] Min Delay (MSec)');\n";
            print "        data.addColumn('number', '[Src to Dst] Max Delay (MSec)');\n";
            $posMap{ $pos[0] } = $posCounter++;
            $posMap{ $pos[1] } = $posCounter++;
        }
        if ( $flags[1] ) {
            print "        data.addColumn('string', '[Src to Dst] Observed Loss');\n";
            print "        data.addColumn('string', 'text1');\n";
            $posMap{ $pos[2] } = $posCounter++;
            $posMap{ $pos[3] } = $posCounter++;
        }
        if ( $flags[2] ) {
            print "        data.addColumn('string', '[Src to Dst] Observed Duplicates');\n";
            print "        data.addColumn('string', 'text2');\n";
            $posMap{ $pos[4] } = $posCounter++;
            $posMap{ $pos[5] } = $posCounter++;
        }

        if ( $flags[3] ) {
            print "        data.addColumn('number', '[Dst to Src] Min Delay (MSec)');\n";
            print "        data.addColumn('number', '[Dst to Src] Max Delay (MSec)');\n";
            $posMap{ $pos[6] } = $posCounter++;
            $posMap{ $pos[7] } = $posCounter++;
        }
        if ( $flags[4] ) {
            print "        data.addColumn('string', '[Dst to Src] Observed Loss');\n";
            print "        data.addColumn('string', 'text1');\n";
            $posMap{ $pos[8] } = $posCounter++;
            $posMap{ $pos[9] } = $posCounter++;
        }
        if ( $flags[5] ) {
            print "        data.addColumn('string', '[Dst to Src] Observed Duplicates');\n";
            print "        data.addColumn('string', 'text2');\n";
            $posMap{ $pos[10] } = $posCounter++;
            $posMap{ $pos[11] } = $posCounter++;
        }

        print "        data.addRows(" . $counter . ");\n";

        $counter = 0;
        foreach my $time ( sort keys %store ) {
            my $date  = ParseDateString( "epoch " . $time );
            my $date2 = UnixDate( $date, "%Y-%m-%d %H:%M:%S" );
            my @array = split( / /, $date2 );
            my @year  = split( /-/, $array[0] );
            my @time  = split( /:/, $array[1] );
            if ( $#year > 1 and $#time > 1 ) {
                print "        data.setValue(" . $counter . ", 0, new Date(" . $year[0] . "," . ( $year[1] - 1 ) . "," . $year[2] . "," . $time[0] . "," . $time[1] . "," . $time[2] . "));\n";
                if ( exists $store{$time}{"src"}{"min"} and $store{$time}{"src"}{"min"} ) {
                    print "        data.setValue(" . $counter . ", " . $posMap{ $pos[0] } . ", " . ( $store{$time}{"src"}{"min"} * 1000 ) . ");\n" if $store{$time}{"src"}{"min"};
                    print "        data.setValue(" . $counter . ", " . $posMap{ $pos[1] } . ", " . ( $store{$time}{"src"}{"max"} * 1000 ) . ");\n" if $store{$time}{"src"}{"max"};
                }
                if ( $store{$time}{"src"}{"lost"} ) {
                    print "        data.setValue(" . $counter . ", " . $posMap{ $pos[2] } . ", 'Loss Observed');\n";
                    print "        data.setValue(" . $counter . ", " . $posMap{ $pos[3] } . ", 'Lost " . $store{$time}{"src"}{"lost"} . " packets out of " . $store{$time}{"src"}{"sent"} . "');\n";
                }
                if ( $store{$time}{"src"}{"dups"} ) {
                    print "        data.setValue(" . $counter . ", " . $posMap{ $pos[4] } . ", 'Duplicates Observed');\n";
                    print "        data.setValue(" . $counter . ", " . $posMap{ $pos[5] } . ", '" . $store{$time}{"src"}{"dups"} . " duplicate packets out of " . $store{$time}{"src"}{"sent"} . "');\n";
                }

                if ( exists $store{$time}{"dest"}{"min"} and $store{$time}{"dest"}{"min"} ) {
                    print "        data.setValue(" . $counter . ", " . $posMap{ $pos[6] } . ", " . ( $store{$time}{"dest"}{"min"} * 1000 ) . ");\n" if $store{$time}{"dest"}{"min"};
                    print "        data.setValue(" . $counter . ", " . $posMap{ $pos[7] } . ", " . ( $store{$time}{"dest"}{"max"} * 1000 ) . ");\n" if $store{$time}{"dest"}{"max"};
                }
                if ( $store{$time}{"dest"}{"lost"} ) {
                    print "        data.setValue(" . $counter . ", " . $posMap{ $pos[8] } . ", 'Loss Observed');\n";
                    print "        data.setValue(" . $counter . ", " . $posMap{ $pos[9] } . ", 'Lost " . $store{$time}{"dest"}{"lost"} . " packets out of " . $store{$time}{"dest"}{"sent"} . "');\n";
                }
                if ( $store{$time}{"dest"}{"dups"} ) {
                    print "        data.setValue(" . $counter . ", " . $posMap{ $pos[10] } . ", 'Duplicates Observed');\n";
                    print "        data.setValue(" . $counter . ", " . $posMap{ $pos[11] } . ", '" . $store{$time}{"dest"}{"dups"} . " duplicate packets out of " . $store{$time}{"dest"}{"sent"} . "');\n";
                }
            }
            $counter++;
        }

        print "        var chart = new google.visualization.AnnotatedTimeLine(document.getElementById('chart_div'));\n";
        if ( $flags[1] or $flags[2] or $flags[4] or $flags[5] ) {
            print "        chart.draw(data, {legendPosition: 'newRow', displayAnnotations: true, colors: ['#ff8800', '#ff0000', '#0088ff', '#0000ff']});\n";
        }
        else {
            print "        chart.draw(data, {legendPosition: 'newRow', colors: ['#ff8800', '#ff0000', '#0088ff', '#0000ff'], displayAnnotations: true});\n";
        }
        print "      }\n";
        print "    </script>\n";
        print "  </head>\n";
        print "  <body>\n";
        print "    <h4 align=\"center\">" . $title . "</h4>\n";
        print "    <div id=\"chart_div\" style=\"width: 900px; height: 400px;\"></div>\n";
    }
    else {
        print "  </head>\n";
        print "  <body>\n";
        print "    <br><br>\n";
        print "    <h2 align=\"center\">Internal Error - Service could not find data to plot for this measurement pair.</h2>\n";
        print "    <br><br>\n";
    }
}
else {
    print "  </head>\n";
    print "  <body>\n";
    print "    <br><br>\n";
    print "    <h2 align=\"center\">Internal Error - Service returned data, but it is not plotable for this measurement pair.  </h2>\n";
    print "    <br><br>\n";
}

print "  </body>\n";
print "</html>\n";

__END__

=head1 SEE ALSO

L<DBI>, L<CGI>, L<CGI::Carp>, L<XML::LibXML>, L<Date::Manip>, L<Socket>, L<POSIX>, L<Time::Local>, L<English>, L<OWP>, L<OWP::Utils>, L<perfSONAR_PS::Utils::ParameterValidation>

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

