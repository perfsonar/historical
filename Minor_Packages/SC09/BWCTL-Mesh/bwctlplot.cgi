#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

bwctlplot.cgi - Graph displaying recent BWCTL data from a pSB database.

=head1 DESCRIPTION

Read the BWCTL portion of the pSB database and graph some length of time.  

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

my $length = q{};
if ( $cgi->param( 'length' ) ) {
    $length = $cgi->param( 'length' );
}

print "Content-type: text/html\n\n";

my $conf = new OWP::Conf( %amidefaults );

my $dbhost = $conf->must_get_val( ATTR => 'CentralDBHost' );
my $dbtype = $conf->must_get_val( ATTR => 'CentralDBType' );
my $dbname = $conf->must_get_val( ATTR => 'BWCentralDBName' );
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

my $endTime = time;
my ( $e_sec, $e_min, $e_hour, $e_mday, $e_mon, $e_year ) = gmtime( $endTime );

#my $startTime = $endTime - ( 5 * $test_interval );
# 86400 = 1 days
$length = 3 unless $length;
my $startTime = $endTime - ( 86400 * $length );
my ( $s_sec, $s_min, $s_hour, $s_mday, $s_mon, $s_year ) = gmtime( $startTime );

#
#  Sanity check the DB to be sure we have the proper date(s) stored
#
my $sql = "select * from DATES where year=" . ( $s_year + 1900 ) . " and month=" . ( $s_mon + 1 );
my $s_date_ref = $dbh->selectall_arrayref( $sql );

$sql = "select * from DATES where year=" . ( $e_year + 1900 ) . " and month=" . ( $e_mon + 1 );
my $e_date_ref = $dbh->selectall_arrayref( $sql );

unless ( exists $e_date_ref->[0] ) {
    push @{ $e_date_ref->[0] }, $s_date_ref->[0][0];
    push @{ $e_date_ref->[0] }, $s_date_ref->[0][1];
}

my $flag       = 1;
my @cursor     = ( $s_date_ref->[0][0], $s_date_ref->[0][1] );
my @dates_list = ();
while ( $flag == 1 ) {
    push @dates_list, [ $cursor[0], sprintf( "%02d", $cursor[1] ) ];
    $flag = 0 if $cursor[0] == $e_date_ref->[0][0] and $cursor[1] == $e_date_ref->[0][1];
    $cursor[1]++;

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
    $sql .= " select node_id, node_name, longname from " . $d->[0] . $d->[1] . "_NODES ";
}

my $ref = $dbh->selectall_arrayref( $sql );

my %map  = ();
my %name = ();
foreach my $r ( @{$ref} ) {
    $map{ $r->[1] }  = $r->[0] if $r->[0] and $r->[1];
    $name{ $r->[1] } = $r->[2] if $r->[2] and $r->[1];
}

#my %r_map = reverse %map;

my %store   = ();
my $counter = 0;
if ( $s_year == $e_year ) {

    # do one select statement

    $sql = q{};
    foreach my $d ( @dates_list ) {
        $sql .= " union " if $sql;
        $sql .= " select * from " . $d->[0] . $d->[1] . "_DATA where send_id=\"" . $map{$send} . "\" and recv_id=\"" . $map{$recv} . "\" and timestamp > '" . time2owptime( $startTime ) . "' and timestamp < '" . time2owptime( $endTime ) . "' ";
    }
    $sql .= ";" if $sql;
    $ref = $dbh->selectall_arrayref( $sql );

    foreach my $r ( @{$ref} ) {
        my $secs = owptime2time( $r->[4] );
        my $bps  = $r->[5];
        $store{$secs}{"src"} = ( $bps ) if $bps;
    }

    $sql = q{};
    foreach my $d ( @dates_list ) {
        $sql .= " union " if $sql;
        $sql .= " select * from " . $d->[0] . $d->[1] . "_DATA where recv_id=\"" . $map{$send} . "\" and send_id=\"" . $map{$recv} . "\" and timestamp > '" . time2owptime( $startTime ) . "' and timestamp < '" . time2owptime( $endTime ) . "' ";
    }
    $sql .= ";" if $sql;
    $ref = $dbh->selectall_arrayref( $sql );

    foreach my $r ( @{$ref} ) {
        my $secs = owptime2time( $r->[4] );
        my $bps  = $r->[5];
        $store{$secs}{"dest"} = eval( ( $bps ) ) if $bps;
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
print "    <title>perfSONAR-PS perfAdmin Bandwidth Graph";
print "</title>\n";

if ( scalar keys %store > 0 ) {

    my $title = q{};
    if ( $name{$recv} and $name{$send} ) {
        $title = "Source: " . $name{$send} . " -- Destination: " . $name{$recv};
    }
    else {
        $title = "Observed Bandwidth";
    }

    print "    <script type=\"text/javascript\" src=\"http://www.google.com/jsapi\"></script>\n";
    print "    <script type=\"text/javascript\">\n";
    print "      google.load(\"visualization\", \"1\", {packages:[\"areachart\"]})\n";
    print "      google.setOnLoadCallback(drawChart);\n";
    print "      function drawChart() {\n";
    print "        var data = new google.visualization.DataTable();\n";
    print "        data.addColumn('datetime', 'Time');\n";

    my %SStats = ( "max" => -1, "min" => "999999", "average" => 0, "current" => 0 );
    my %DStats = ( "max" => -1, "min" => "999999", "average" => 0, "current" => 0 );
    my $scounter = 0;
    my $dcounter = 0;
    foreach my $time ( sort keys %store ) {
        if ( exists $store{$time}{"src"} and $store{$time}{"src"} ) {
            $SStats{"average"} += $store{$time}{"src"};
            $SStats{"current"} = $store{$time}{"src"};
            $SStats{"max"} = $store{$time}{"src"} if $store{$time}{"src"} and ( $store{$time}{"src"} > $SStats{"max"} );
            $scounter++;
        }
        if ( exists $store{$time}{"dest"} and $store{$time}{"dest"} ) {
            $DStats{"average"} += $store{$time}{"dest"};
            $DStats{"current"} = $store{$time}{"dest"};
            $DStats{"max"} = $store{$time}{"dest"} if $store{$time}{"dest"} and ( $store{$time}{"dest"} > $DStats{"max"} );
            $dcounter++;
        }
    }
    $SStats{"average"} /= $scounter if $scounter;
    $DStats{"average"} /= $dcounter if $dcounter;

    my $mod   = q{};
    my $scale = q{};
    $scale = $SStats{"max"};
    $scale = $DStats{"max"} if $DStats{"max"} > $scale;
    if ( $scale < 1000 ) {
        $scale = 1;
    }
    elsif ( $scale < 1000000 ) {
        $mod   = "K";
        $scale = 1000;
    }
    elsif ( $scale < 1000000000 ) {
        $mod   = "M";
        $scale = 1000000;
    }
    elsif ( $scale < 1000000000000 ) {
        $mod   = "G";
        $scale = 1000000000;
    }

    print "        data.addColumn('number', 'Source -> Destination in " . $mod . "bps');\n";
    print "        data.addColumn('number', 'Destination -> Source in " . $mod . "bps');\n";
    print "        data.addRows(" . $counter . ");\n";

    $counter = 0;
    foreach my $time ( sort keys %store ) {
        my $date  = ParseDateString( "epoch " . $time );
        my $date2 = UnixDate( $date, "%Y-%m-%d %H:%M:%S" );
        my @array = split( / /, $date2 );
        my @year  = split( /-/, $array[0] );
        my @time  = split( /:/, $array[1] );
        if ( $#year > 1 and $#time > 1 ) {
            if ( exists $store{$time}{"src"} and $store{$time}{"src"} ) {
                print "        data.setValue(" . $counter . ", 0, new Date(" . $year[0] . "," . ( $year[1] - 1 ) . "," . $year[2] . "," . $time[0] . "," . $time[1] . "," . $time[2] . "));\n";
                $store{$time}{"src"} /= $scale if $scale;
                print "        data.setValue(" . $counter . ", 1, " . $store{$time}{"src"} . ");\n" if exists $store{$time}{"src"};
            }
            if ( exists $store{$time}{"dest"} and $store{$time}{"dest"} ) {
                print "        data.setValue(" . $counter . ", 0, new Date(" . $year[0] . "," . ( $year[1] - 1 ) . "," . $year[2] . "," . $time[0] . "," . $time[1] . "," . $time[2] . "));\n" unless ( exists $store{$time}{"src"} and $store{$time}{"src"} );
                $store{$time}{"dest"} /= $scale if $scale;
                print "        data.setValue(" . $counter . ", 2, " . $store{$time}{"dest"} . ");\n" if exists $store{$time}{"dest"};
            }
            $counter++ if ( exists $store{$time}{"dest"} and $store{$time}{"dest"} ) or ( exists $store{$time}{"src"} and $store{$time}{"src"} );
        }
    }
    print "        var formatter = new google.visualization.DateFormat({formatType: 'short'});\n";
    print "        formatter.format(data, 0);\n";
    print "        var chart = new google.visualization.AreaChart(document.getElementById('chart_div'));\n";
    print "        chart.draw(data, {legendFontSize: 12, axisFontSize: 12, titleFontSize: 16, colors: ['#00cc00', '#0000ff'], width: 900, height: 400, min: 0, legend: 'bottom', title: '" . $title . "', titleY: '" . $mod . "bps'});\n";
    print "      }\n";
    print "    </script>\n";
    print "  </head>\n";
    print "  <body>\n";

    print "    <center><div id=\"chart_div\" style=\"width: 900px; height: 400px;\"></div></center>\n";

    print "    <table border=\"0\" cellpadding=\"0\" width=\"85%\" align=\"center\">";

    print "      <tr>\n";
    my $temp = q{};
    if ( $DStats{"max"} and $DStats{"average"} and $DStats{"current"} ) {
        print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Maximum <b>" . $name{$send} . "</b> -> <b>" . $name{$recv} . "</b></font></td>\n";
        $temp = scaleValue( { value => $SStats{"max"} } );
        printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
        print "        <td align=\"right\" width=\"10%\"><br></td>\n";
        print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Maximum <b>" . $name{$recv} . "</b> -> <b>" . $name{$send} . "</b></font></td>\n";
        $temp = scaleValue( { value => $DStats{"max"} } );
        printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
    }
    else {
        print "        <td align=\"right\" width=\"20%\"><br></td>\n";
        print "        <td align=\"left\" width=\"45%\"><font size=\"-1\">Maximum <b>" . $name{$send} . "</b> -> <b>" . $name{$recv} . "</b></font></td>\n";
        $temp = scaleValue( { value => $SStats{"max"} } );
        printf( "        <td align=\"left\" width=\"35%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
    }
    print "      </tr>\n";

    print "      <tr>\n";
    if ( $DStats{"max"} and $DStats{"average"} and $DStats{"current"} ) {

        print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Average <b>" . $name{$send} . "</b> -> <b>" . $name{$recv} . "</b></font></td>\n";
        $temp = scaleValue( { value => $SStats{"average"} } );
        printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
        print "        <td align=\"right\" width=\"10%\"><br></td>\n";
        print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Average <b>" . $name{$recv} . "</b> -> <b>" . $name{$send} . "</b></font></td>\n";
        $temp = scaleValue( { value => $DStats{"average"} } );
        printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );

    }
    else {
        print "        <td align=\"right\" width=\"20%\"><br></td>\n";
        print "        <td align=\"left\" width=\"45%\"><font size=\"-1\">Average <b>" . $name{$send} . "</b> -> <b>" . $name{$recv} . "</b></font></td>\n";
        $temp = scaleValue( { value => $SStats{"average"} } );
        printf( "        <td align=\"left\" width=\"35%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
    }
    print "      </tr>\n";

    print "      <tr>\n";
    if ( $DStats{"max"} and $DStats{"average"} and $DStats{"current"} ) {

        print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Last <b>" . $name{$send} . "</b> -> <b>" . $name{$recv} . "</b></font></td>\n";
        $temp = scaleValue( { value => $SStats{"current"} } );
        printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
        print "        <td align=\"right\" width=\"10%\"><br></td>\n";
        print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Last <b>" . $name{$recv} . "</b> -> <b>" . $name{$send} . "</b></font></td>\n";
        $temp = scaleValue( { value => $DStats{"current"} } );
        printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );

    }
    else {
        print "        <td align=\"right\" width=\"20%\"><br></td>\n";
        print "        <td align=\"left\" width=\"45%\"><font size=\"-1\">Last <b>" . $name{$send} . "</b> -> <b>" . $name{$recv} . "</b></font></td>\n";
        $temp = scaleValue( { value => $SStats{"current"} } );
        printf( "        <td align=\"left\" width=\"35%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
    }
    print "      </tr>\n";

    print "    </table>\n";
}
else {
    print "  </head>\n";
    print "  <body>\n";
    print "    <br><br>\n";
    print "    <h2 align=\"center\">Data Not Found - Try again later.</h2>\n";
    print "    <br><br>\n";
}

print "  </body>\n";
print "</html>\n";

sub scaleValue {
    my $parameters = validateParams( @_, { value => 1 } );
    my %result = ();
    if ( $parameters->{"value"} < 1000 ) {
        $result{"value"} = $parameters->{"value"};
        $result{"mod"}   = q{};
    }
    elsif ( $parameters->{"value"} < 1000000 ) {
        $result{"value"} = $parameters->{"value"} / 1000;
        $result{"mod"}   = "K";
    }
    elsif ( $parameters->{"value"} < 1000000000 ) {
        $result{"value"} = $parameters->{"value"} / 1000000;
        $result{"mod"}   = "M";
    }
    elsif ( $parameters->{"value"} < 1000000000000 ) {
        $result{"value"} = $parameters->{"value"} / 1000000000;
        $result{"mod"}   = "G";
    }
    return \%result;
}

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

