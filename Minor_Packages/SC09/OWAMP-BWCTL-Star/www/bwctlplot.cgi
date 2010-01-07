#!/usr/bin/perl -w

use strict;
use warnings;

use DBI;
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use XML::LibXML;
use Date::Manip;
use Socket;
use POSIX;
use Time::Local 'timelocal_nocheck';
use English qw( -no_match_vars );

use lib "/home/aaron/owamp/lib";
use lib "/opt/perfsonar_ps/perfsonarbuoy_bwctl/lib";

use OWP;
use OWP::Utils;
use bwdb;
use perfSONAR_PS::Utils::ParameterValidation;

my %amidefaults;

BEGIN {
    %amidefaults = (
        CONFDIR => "/opt/perfsonar_ps/perfsonarbuoy_bwctl/etc",
        LIBDIR  => "/opt/perfsonar_ps/perfsonarbuoy_bwctl/lib",
    );
}

my $cgi  = CGI->new();

my $sender            = $cgi->param('sender');
my $receiver          = $cgi->param('receiver');
my $receiver_address  = $cgi->param('receiver_address');
my $sender_address    = $cgi->param('sender_address');
my $start_time        = $cgi->param( 'start_time' );
my $end_time          = $cgi->param( 'end_time' );
my $duration          = $cgi->param( 'duration' );

unless ($sender and $receiver) {
    croak "Must Supply 'sender' parameter, aborting.\n";
}

print "Content-type: text/html\n\n";

my $conf = new OWP::Conf( %amidefaults );

my $dbhost = $conf->get_val( ATTR => 'CentralDBHost' );
my $dbtype = $conf->must_get_val( ATTR => 'CentralDBType' );
my $dbname = $conf->must_get_val( ATTR => 'BWCentralDBName' );
my $dbuser = $conf->must_get_val( ATTR => 'CGIDBUser' );
my $dbpass = $conf->get_val( ATTR      => 'CGIDBPass' );

$dbhost = "localhost" unless ($dbhost);

my $dbsource = $dbtype . ":" . $dbname . ":" . $dbhost;
my $dbh      = DBI->connect(
    $dbsource,
    $dbuser, $dbpass,
    {
        RaiseError => 0,
        PrintError => 1
    }
) || croak "Couldn't connect to database";

$end_time = time unless ($end_time);
$duration = 2 unless $duration;
$start_time = $end_time - ( 86400 * $duration ) unless ($start_time);

my %store = ();
my %bwvals = ();

my ($status, $res) = bwdb_lookup_nodes({ dbh => $dbh, first => owptstampi( time2owptime($start_time) ), last => owptstampi( time2owptime( $end_time ) ) });
die ($res) if ($status != 0);

my $nodes = $res;

my $bwdb = bwdb_prep(
		DBH         => $dbh,
		RECV_NAME   => $receiver,
		RECV_ADDR   => $receiver_address,
		SEND_NAME   => $sender,
		SEND_ADDR   => $sender_address,
		FIRST       => owptstampi( time2owptime($start_time) ),
		LAST        => owptstampi( time2owptime($end_time) ),
		BWHASH      => \%bwvals,
		) or die "Unable to init owp data request";

while ( bwdb_fetch( BWDBH => $bwdb ) ) {
	my ($test_time, $test_throughput);

	$test_time = owptime2time(owpi2owp($bwvals{'TIME'}));
	$test_throughput = eval( $bwvals{'THROUGHPUT'} ) if ($bwvals{'THROUGHPUT'});

	$store{$test_time}->{"src"} = $test_throughput if ($test_throughput);
}

my $bwdb = bwdb_prep(
		DBH         => $dbh,
		RECV_NAME   => $sender,
		RECV_ADDR   => $sender_address,
		SEND_NAME   => $receiver,
		SEND_ADDR   => $receiver_address,
		FIRST       => owptstampi( time2owptime($start_time) ),
		LAST        => owptstampi( time2owptime($end_time) ),
		BWHASH      => \%bwvals,
		) or die "Unable to init owp data request";

while ( bwdb_fetch( BWDBH => $bwdb ) ) {
	my ($test_time, $test_throughput);

	$test_time = owptime2time(owpi2owp($bwvals{'TIME'}));
	$test_throughput = eval( $bwvals{'THROUGHPUT'} ) if ($bwvals{'THROUGHPUT'});

	$store{$test_time}->{"dest"} = $test_throughput if ($test_throughput);
}

print "<html>\n";
print "  <head>\n";
print "    <title>perfSONAR-PS perfAdmin Bandwidth Graph";
print "</title>\n";

if ( scalar keys %store == 0 ) {
    print "  </head>\n";
    print "  <body>\n";
    print "    <br><br>\n";
    print "    <h2 align=\"center\">Data Not Found - Try again later.</h2>\n";
    print "    <br><br>\n";
}
else {
    my $title = q{};
    if ( $nodes->{$receiver}->[0]->{longname} and $nodes->{$sender}->[0]->{longname} ) {
        $title = "Source: " . $nodes->{$sender}->[0]->{longname} . " -- Destination: " . $nodes->{$receiver}->[0]->{longname};
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

    my %SStats   = ( "max" => -1, "min" => "999999", "average" => 0, "current" => 0 );
    my %DStats   = ( "max" => -1, "min" => "999999", "average" => 0, "current" => 0 );
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
    print "        data.addRows(" . scalar(keys %store) . ");\n";
    
    my $counter = 0;
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
        print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Maximum <b>" . $nodes->{$sender}->[0]->{longname} . "</b> -> <b>" . $nodes->{$receiver}->[0]->{longname} . "</b></font></td>\n";
        $temp = scaleValue( { value => $SStats{"max"} } );
        printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
        print "        <td align=\"right\" width=\"10%\"><br></td>\n";
        print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Maximum <b>" . $nodes->{$receiver}->[0]->{longname} . "</b> -> <b>" . $nodes->{$sender}->[0]->{longname} . "</b></font></td>\n";
        $temp = scaleValue( { value => $DStats{"max"} } );
        printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
    }
    else {
        print "        <td align=\"right\" width=\"20%\"><br></td>\n";
        print "        <td align=\"left\" width=\"45%\"><font size=\"-1\">Maximum <b>" . $nodes->{$sender}->[0]->{longname} . "</b> -> <b>" . $nodes->{$receiver}->[0]->{longname} . "</b></font></td>\n";
        $temp = scaleValue( { value => $SStats{"max"} } );
        printf( "        <td align=\"left\" width=\"35%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
    }
    print "      </tr>\n";

    print "      <tr>\n";
    if ( $DStats{"max"} and $DStats{"average"} and $DStats{"current"} ) {

        print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Average <b>" . $nodes->{$sender}->[0]->{longname} . "</b> -> <b>" . $nodes->{$receiver}->[0]->{longname} . "</b></font></td>\n";
        $temp = scaleValue( { value => $SStats{"average"} } );
        printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
        print "        <td align=\"right\" width=\"10%\"><br></td>\n";
        print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Average <b>" . $nodes->{$receiver}->[0]->{longname} . "</b> -> <b>" . $nodes->{$sender}->[0]->{longname} . "</b></font></td>\n";
        $temp = scaleValue( { value => $DStats{"average"} } );
        printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );

    }
    else {
        print "        <td align=\"right\" width=\"20%\"><br></td>\n";
        print "        <td align=\"left\" width=\"45%\"><font size=\"-1\">Average <b>" . $nodes->{$sender}->[0]->{longname} . "</b> -> <b>" . $nodes->{$receiver}->[0]->{longname} . "</b></font></td>\n";
        $temp = scaleValue( { value => $SStats{"average"} } );
        printf( "        <td align=\"left\" width=\"35%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
    }
    print "      </tr>\n";

    print "      <tr>\n";
    if ( $DStats{"max"} and $DStats{"average"} and $DStats{"current"} ) {

        print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Last <b>" . $nodes->{$sender}->[0]->{longname} . "</b> -> <b>" . $nodes->{$receiver}->[0]->{longname} . "</b></font></td>\n";
        $temp = scaleValue( { value => $SStats{"current"} } );
        printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
        print "        <td align=\"right\" width=\"10%\"><br></td>\n";
        print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Last <b>" . $nodes->{$receiver}->[0]->{longname} . "</b> -> <b>" . $nodes->{$sender}->[0]->{longname} . "</b></font></td>\n";
        $temp = scaleValue( { value => $DStats{"current"} } );
        printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );

    }
    else {
        print "        <td align=\"right\" width=\"20%\"><br></td>\n";
        print "        <td align=\"left\" width=\"45%\"><font size=\"-1\">Last <b>" . $nodes->{$sender}->[0]->{longname} . "</b> -> <b>" . $nodes->{$receiver}->[0]->{longname} . "</b></font></td>\n";
        $temp = scaleValue( { value => $SStats{"current"} } );
        printf( "        <td align=\"left\" width=\"35%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
    }
    print "      </tr>\n";

    print "    </table>\n";
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
