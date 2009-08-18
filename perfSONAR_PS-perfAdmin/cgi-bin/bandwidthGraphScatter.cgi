#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

bandwidthGraph.cgi - CGI script that graphs the output of a perfSONAR MA that
delivers bandwidth data.  

=head1 DESCRIPTION

Given a url of an MA, and a key value (corresponds to a specific bandwidth
result) graph using the Google graph API.  This particular graph is a
'scatter plot' that does not feature any lines.

=cut

use CGI;
use XML::LibXML;
use Date::Manip;
use Socket;
use POSIX;

use FindBin qw($RealBin);
my $basedir = "$RealBin/";
use lib "$RealBin/../lib";

use perfSONAR_PS::Client::MA;
use perfSONAR_PS::Common qw( extract find );
use perfSONAR_PS::Utils::ParameterValidation;

my $cgi = new CGI;
print "Content-type: text/html\n\n";
if ( $cgi->param( 'key' ) and $cgi->param( 'url' ) ) {

    my $ma = new perfSONAR_PS::Client::MA( { instance => $cgi->param( 'url' ) } );

    my @eventTypes = ();
    my $parser     = XML::LibXML->new();
    my $sec        = time;

    my $subject = "  <nmwg:key id=\"key-1\">\n";
    $subject .= "    <nmwg:parameters id=\"parameters-key-1\">\n";
    $subject .= "      <nmwg:parameter name=\"maKey\">" . $cgi->param( 'key' ) . "</nmwg:parameter>\n";
    $subject .= "    </nmwg:parameters>\n";
    $subject .= "  </nmwg:key>  \n";

    my $time;
    if ( $cgi->param( 'length' ) ) {
        $time = $cgi->param( 'length' );
    }
    else {
        $time = 86400;
    }

    my $result = $ma->setupDataRequest(
        {
            start      => ( $sec - $time ),
            end        => $sec,
            subject    => $subject,
            eventTypes => \@eventTypes
        }
    );

    my $doc1 = $parser->parse_string( $result->{"data"}->[0] );
    my $datum1 = find( $doc1->getDocumentElement, "./*[local-name()='datum']", 0 );

    my $doc2;
    my $datum2;
    my $result2;
    if ( $cgi->param( 'key2' ) ) {
        my $subject2 = "  <nmwg:key id=\"key-2\">\n";
        $subject2 .= "    <nmwg:parameters id=\"parameters-key-2\">\n";
        $subject2 .= "      <nmwg:parameter name=\"maKey\">" . $cgi->param( 'key2' ) . "</nmwg:parameter>\n";
        $subject2 .= "    </nmwg:parameters>\n";
        $subject2 .= "  </nmwg:key>  \n";

        $result2 = $ma->setupDataRequest(
            {
                start      => ( $sec - $time ),
                end        => $sec,
                subject    => $subject2,
                eventTypes => \@eventTypes
            }
        );

        $doc2 = $parser->parse_string( $result2->{"data"}->[0] );
        $datum2 = find( $doc2->getDocumentElement, "./*[local-name()='datum']", 0 );
    }

    my %store = ();
    if ( $datum1 ) {
        foreach my $dt ( $datum1->get_nodelist ) {
            my $secs = UnixDate( $dt->getAttribute( "timeValue" ), "%s" );
            $store{$secs}{"src"} = eval( $dt->getAttribute( "throughput" ) ) if $secs and $dt->getAttribute( "throughput" );
        }
    }
    if ( $datum2 ) {
        foreach my $dt ( $datum2->get_nodelist ) {
            my $secs = UnixDate( $dt->getAttribute( "timeValue" ), "%s" );
            $store{$secs}{"dest"} = eval( $dt->getAttribute( "throughput" ) ) if $secs and $dt->getAttribute( "throughput" );
        }
    }

    my $counter = 0;
    foreach my $time ( keys %store ) {
        $counter++;
    }

    print "<html>\n";
    print "  <head>\n";
    print "    <title>perfSONAR-PS perfAdmin Bandwidth Graph";
    if ( $cgi->param( 'type' ) ) {
        print " " . $cgi->param( 'type' );
    }
    print "</title>\n";

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
            $title = "Observed Bandwidth";
        }

        print "    <script type=\"text/javascript\" src=\"http://www.google.com/jsapi\"></script>\n";
        print "    <script type=\"text/javascript\">\n";
        print "      google.load(\"visualization\", \"1\", {packages:[\"linechart\"]})\n";
        print "      google.setOnLoadCallback(drawChart);\n";
        print "      function drawChart() {\n";
        print "        var data = new google.visualization.DataTable();\n";
        print "        data.addColumn('datetime', 'Time');\n";

        my %SStats   = ();
        my %DStats   = ();
        my $scounter = 0;
        my $dcounter = 0;
        foreach my $time ( sort keys %store ) {
            if ( exists $store{$time}{"src"} and $store{$time}{"src"} ) {
                $SStats{"average"} += $store{$time}{"src"};
                $SStats{"current"} = $store{$time}{"src"};
                $SStats{"max"} = $store{$time}{"src"} if $store{$time}{"src"} > $SStats{"max"};
                $scounter++;
            }
            if ( exists $store{$time}{"dest"} and $store{$time}{"dest"} ) {
                $DStats{"average"} += $store{$time}{"dest"};
                $DStats{"current"} = $store{$time}{"dest"};
                $DStats{"max"} = $store{$time}{"dest"} if $store{$time}{"dest"} > $DStats{"max"};
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

        print "        data.addColumn('number', '" . $cgi->param( 'shost' ) . " -> " . $cgi->param( 'dhost' ) . " in " . $mod . "bps');\n";
        if ( $cgi->param( 'key2' ) ) {
            print "        data.addColumn('number', '" . $cgi->param( 'dhost' ) . " -> " . $cgi->param( 'shost' ) . " in " . $mod . "bps');\n";
        }

        my $doc1 = $parser->parse_string( $result->{"data"}->[0] );
        my $datum1 = find( $doc1->getDocumentElement, "./*[local-name()='datum']", 0 );

        my $doc2;
        my $datum2;
        if ( $cgi->param( 'key2' ) ) {
            $doc2 = $parser->parse_string( $result2->{"data"}->[0] );
            $datum2 = find( $doc2->getDocumentElement, "./*[local-name()='datum']", 0 );
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
        print "        var chart = new google.visualization.LineChart(document.getElementById('chart_div'));\n";
        print "        chart.draw(data, {legendFontSize: 12, axisFontSize: 12, titleFontSize: 16, colors: ['#00cc00', '#0000ff'], width: 900, height: 400, min: 0, legend: 'bottom', title: '" . $title . "', titleY: '" . $mod . "bps', lineSize: '0'});\n";
        print "      }\n";
        print "    </script>\n";
        print "  </head>\n";
        print "  <body>\n";

        print "    <div id=\"chart_div\" style=\"width: 900px; height: 400px;\"></div>\n";

        print "    <table border=\"0\" cellpadding=\"0\" width=\"85%\" align=\"center\">";
        print "      <tr>\n";
        print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Maximum <b>" . $cgi->param( 'shost' ) . "</b> -> <b>" . $cgi->param( 'dhost' ) . "</b></font></td>\n";
        my $temp = scaleValue( { value => $SStats{"max"} } );
        printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
        print "        <td align=\"right\" width=\"10%\"><br></td>\n";
        print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Maximum <b>" . $cgi->param( 'dhost' ) . "</b> -> <b>" . $cgi->param( 'shost' ) . "</b></font></td>\n";
        $temp = scaleValue( { value => $DStats{"max"} } );
        printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
        print "      <tr>\n";
        print "      <tr>\n";
        print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Average <b>" . $cgi->param( 'shost' ) . "</b> -> <b>" . $cgi->param( 'dhost' ) . "</b></font></td>\n";
        $temp = scaleValue( { value => $SStats{"average"} } );
        printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
        print "        <td align=\"right\" width=\"10%\"><br></td>\n";
        print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Average <b>" . $cgi->param( 'dhost' ) . "</b> -> <b>" . $cgi->param( 'shost' ) . "</b></font></td>\n";
        $temp = scaleValue( { value => $DStats{"average"} } );
        printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
        print "      <tr>\n";
        print "      <tr>\n";
        print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Last <b>" . $cgi->param( 'shost' ) . "</b> -> <b>" . $cgi->param( 'dhost' ) . "</b></font></td>\n";
        $temp = scaleValue( { value => $SStats{"current"} } );
        printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
        print "        <td align=\"right\" width=\"10%\"><br></td>\n";
        print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Last <b>" . $cgi->param( 'dhost' ) . "</b> -> <b>" . $cgi->param( 'shost' ) . "</b></font></td>\n";
        $temp = scaleValue( { value => $DStats{"current"} } );
        printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
        print "      <tr>\n";
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
}
else {
    print "<html><head><title>perfSONAR-PS perfAdmin Delay Graph</title></head>";
    print "<body><h2 align=\"center\">Graph error, cannot find 'key' or 'URL' to contact; Close window and try again.</h2></body></html>";
}

=head2 scaleValue ( { value } )

Given a value, return the value scaled to a magnitude.

=cut

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

L<CGI>, L<XML::LibXML>, L<Date::Manip>, L<Socket>, L<POSIX>,
L<perfSONAR_PS::Client::MA>, L<perfSONAR_PS::Common>,
L<perfSONAR_PS::Utils::ParameterValidation>

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

Copyright (c) 2007-2009, Internet2

All rights reserved.

=cut
