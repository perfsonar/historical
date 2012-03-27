#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

bandwidthGraphFlash.cgi - CGI script that graphs the output of a perfSONAR MA
that delivers bandwidth data.  This particular graph is a Flash baed
'line plot'.  

=head1 DESCRIPTION

Given a url of an MA, and a key value (corresponds to a specific bandwidth
result) graph using the Google graph API.  Note this specific instance uses a
flash-based API so browsers will be required to have an instance of a flash
player installed.  

=cut

use CGI;
use XML::LibXML;
use Date::Manip;
use Socket;
use POSIX;
use Time::Local 'timelocal_nocheck';
use English qw( -no_match_vars );

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
    my ( $sec, $frac ) = Time::HiRes::gettimeofday;

    my $subject = "  <nmwg:key id=\"key-1\">\n";
    $subject .= "    <nmwg:parameters id=\"parameters-key-1\">\n";
    $subject .= "      <nmwg:parameter name=\"maKey\">" . $cgi->param( 'key' ) . "</nmwg:parameter>\n";
    $subject .= "    </nmwg:parameters>\n";
    $subject .= "  </nmwg:key>  \n";

    my $start;
    my $end;
    if ( $cgi->param( 'length' ) ) {
        $start = $sec - $cgi->param( 'length' );
        $end   = $sec;
    }
    elsif ( $cgi->param( 'smon' ) or $cgi->param( 'sday' ) or $cgi->param( 'syear' ) or $cgi->param( 'dmon' ) or $cgi->param( 'dday' ) or $cgi->param( 'dyear' ) ) {
        if ( $cgi->param( 'smon' ) and $cgi->param( 'sday' ) and $cgi->param( 'syear' ) and $cgi->param( 'dmon' ) and $cgi->param( 'dday' ) and $cgi->param( 'dyear' ) ) {
            $start = timelocal_nocheck 0, 0, 0, ( $cgi->param( 'sday' ) - 1 ), ( $cgi->param( 'smon' ) - 1 ), ( $cgi->param( 'syear' ) - 1900 );
            $end   = timelocal_nocheck 0, 0, 0, ( $cgi->param( 'dday' ) - 1 ), ( $cgi->param( 'dmon' ) - 1 ), ( $cgi->param( 'dyear' ) - 1900 );
        }
        else {
            print "<html><head><title>perfSONAR-PS perfAdmin Bandwidth Graph</title></head>";
            print "<body><h2 align=\"center\">Graph error; Date not correctly entered.</h2></body></html>";
            exit( 1 );
        }
    }
    else {
        $start = $sec - 86400;
        $end   = $sec;
    }

    my $result = $ma->setupDataRequest(
        {
            start      => $start,
            end        => $end,
            subject    => $subject,
            eventTypes => \@eventTypes
        }
    );

    my $doc1 = q{};
    eval { $doc1 = $parser->parse_string( $result->{"data"}->[0] ); };
    if ( $EVAL_ERROR ) {
        print "<html><head><title>perfSONAR-PS perfAdmin Bandwidth Graph</title></head>";
        print "<body><h2 align=\"center\">Cannot parse XML response from service.</h2></body></html>";
        exit( 1 );
    }
    
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
                start      => $start,
                end        => $end,
                subject    => $subject2,
                eventTypes => \@eventTypes
            }
        );

        eval { $doc2 = $parser->parse_string( $result2->{"data"}->[0] ); };
        if ( $EVAL_ERROR ) {
            print "<html><head><title>perfSONAR-PS perfAdmin Bandwidth Graph</title></head>";
            print "<body><h2 align=\"center\">Cannot parse XML response from service.</h2></body></html>";
            exit( 1 );
        }
        
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
        print "      google.load(\"visualization\", \"1\", {packages:[\"annotatedtimeline\"]});\n";
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

        print "        data.addColumn('number', 'Source -> Destination in " . $mod . "bps');\n";
        if ( $cgi->param( 'key2' ) ) {
            print "        data.addColumn('number', 'Destination -> Source in " . $mod . "bps');\n";
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
                    print "        data.setValue(" . $counter . ", 1, " . sprintf( "%.2f", $store{$time}{"src"} ) . ");\n" if exists $store{$time}{"src"};
                }
                if ( exists $store{$time}{"dest"} and $store{$time}{"dest"} ) {
                    print "        data.setValue(" . $counter . ", 0, new Date(" . $year[0] . "," . ( $year[1] - 1 ) . "," . $year[2] . "," . $time[0] . "," . $time[1] . "," . $time[2] . "));\n" unless ( exists $store{$time}{"src"} and $store{$time}{"src"} );
                    $store{$time}{"dest"} /= $scale if $scale;
                    print "        data.setValue(" . $counter . ", 2, " . sprintf( "%.2f", $store{$time}{"dest"} ) . ");\n" if exists $store{$time}{"dest"};
                }
                $counter++ if ( exists $store{$time}{"dest"} and $store{$time}{"dest"} ) or ( exists $store{$time}{"src"} and $store{$time}{"src"} );
            }
        }

        print "        var chart = new google.visualization.AnnotatedTimeLine(document.getElementById('chart_div'));\n";
        print "        chart.draw(data, {legend: 'none', colors: ['#00cc00', '#0000ff']});\n";
        print "      }\n";
        print "    </script>\n";
        print "  </head>\n";
        print "  <body>\n";
        print "    <h3 align=\"center\">" . $title . "</h3>\n";
        print "    <center><div id=\"chart_div\" style=\"width: 900px; height: 400px;\"></div></center><br>\n";
        print "    <table border=\"0\" cellpadding=\"0\" width=\"85%\" align=\"center\">";
        print "      <tr>\n";
        my $temp = q{};

        if ( $DStats{"max"} and $DStats{"average"} and $DStats{"current"} ) {
            print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Maximum <b>" . $cgi->param( 'shost' ) . "</b> -> <b>" . $cgi->param( 'dhost' ) . "</b></font></td>\n";
            $temp = scaleValue( { value => $SStats{"max"} } );
            printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
            print "        <td align=\"right\" width=\"10%\"><br></td>\n";
            print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Maximum <b>" . $cgi->param( 'dhost' ) . "</b> -> <b>" . $cgi->param( 'shost' ) . "</b></font></td>\n";
            $temp = scaleValue( { value => $DStats{"max"} } );
            printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
        }
        else {
            print "        <td align=\"right\" width=\"20%\"><br></td>\n";
            print "        <td align=\"left\" width=\"45%\"><font size=\"-1\">Maximum <b>" . $cgi->param( 'shost' ) . "</b> -> <b>" . $cgi->param( 'dhost' ) . "</b></font></td>\n";
            $temp = scaleValue( { value => $SStats{"max"} } );
            printf( "        <td align=\"left\" width=\"35%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
        }
        print "      </tr>\n";

        print "      <tr>\n";
        if ( $DStats{"max"} and $DStats{"average"} and $DStats{"current"} ) {
            print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Average <b>" . $cgi->param( 'shost' ) . "</b> -> <b>" . $cgi->param( 'dhost' ) . "</b></font></td>\n";
            $temp = scaleValue( { value => $SStats{"average"} } );
            printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
            print "        <td align=\"right\" width=\"10%\"><br></td>\n";
            print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Average <b>" . $cgi->param( 'dhost' ) . "</b> -> <b>" . $cgi->param( 'shost' ) . "</b></font></td>\n";
            $temp = scaleValue( { value => $DStats{"average"} } );
            printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
        }
        else {
            print "        <td align=\"right\" width=\"20%\"><br></td>\n";
            print "        <td align=\"left\" width=\"45%\"><font size=\"-1\">Average <b>" . $cgi->param( 'shost' ) . "</b> -> <b>" . $cgi->param( 'dhost' ) . "</b></font></td>\n";
            $temp = scaleValue( { value => $SStats{"average"} } );
            printf( "        <td align=\"left\" width=\"35%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
        }
        print "      </tr>\n";

        print "      <tr>\n";
        if ( $DStats{"max"} and $DStats{"average"} and $DStats{"current"} ) {
            print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Last <b>" . $cgi->param( 'shost' ) . "</b> -> <b>" . $cgi->param( 'dhost' ) . "</b></font></td>\n";
            $temp = scaleValue( { value => $SStats{"current"} } );
            printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
            print "        <td align=\"right\" width=\"10%\"><br></td>\n";
            print "        <td align=\"left\" width=\"35%\"><font size=\"-1\">Last <b>" . $cgi->param( 'dhost' ) . "</b> -> <b>" . $cgi->param( 'shost' ) . "</b></font></td>\n";
            $temp = scaleValue( { value => $DStats{"current"} } );
            printf( "        <td align=\"right\" width=\"10%\"><font size=\"-1\">%.2f " . $temp->{"mod"} . "bps</font></td>\n", $temp->{"value"} );
        }
        else {
            print "        <td align=\"right\" width=\"20%\"><br></td>\n";
            print "        <td align=\"left\" width=\"45%\"><font size=\"-1\">Last <b>" . $cgi->param( 'shost' ) . "</b> -> <b>" . $cgi->param( 'dhost' ) . "</b></font></td>\n";
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
    exit( 1 );
}
else {
    print "<html><head><title>perfSONAR-PS perfAdmin Bandwidth Graph</title></head>";
    print "<body><h2 align=\"center\">Graph error, cannot find 'key' or 'URL' to contact; Close window and try again.</h2></body></html>";
    exit( 1 );
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

L<CGI>, L<XML::LibXML>, L<Date::Manip>, L<Socket>, L<POSIX>, L<Time::Local>,
L<English>, L<perfSONAR_PS::Client::MA>, L<perfSONAR_PS::Common>,
L<perfSONAR_PS::Utils::ParameterValidation>

To join the 'perfSONAR-PS Users' mailing list, please visit:

  https://lists.internet2.edu/sympa/info/perfsonar-ps-users

The perfSONAR-PS subversion repository is located at:

  http://anonsvn.internet2.edu/svn/perfSONAR-PS/trunk

Questions and comments can be directed to the author, or the mailing list.
Bugs, feature requests, and improvements can be directed here:

  http://code.google.com/p/perfsonar-ps/issues/list

=head1 VERSION

$Id$

=head1 AUTHOR

Jason Zurawski, zurawski@internet2.edu

=head1 LICENSE

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 COPYRIGHT

Copyright (c) 2007-2010, Internet2

All rights reserved.

=cut
