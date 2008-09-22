#!/usr/bin/perl -w

use strict;
use warnings;

=head1 NAME

utilizationGraph.cgi - CGI script that graphs the output of a perfSONAR MA that
delivers utilization data.  

=head1 DESCRIPTION

Given a url of an MA, and a key value (corresponds to a specific pair [in and
out] of utilization results) graph using the Google graph API.

=cut

use CGI;
use XML::LibXML;
use Date::Manip;

use lib "/usr/local/perfSONAR-PS/lib";

use perfSONAR_PS::Client::MA;
use perfSONAR_PS::Common qw( extract find );

my $cgi = new CGI;
print "Content-type: text/html\n\n";
if ( ( $cgi->param('key1') or $cgi->param('key2') ) and $cgi->param('url') ) {

    my $ma = new perfSONAR_PS::Client::MA( { instance => $cgi->param('url') } );

    my @eventTypes = ();
    my $parser     = XML::LibXML->new();
    my ( $sec, $frac ) = Time::HiRes::gettimeofday;

    # 'in' data
    my $subject = "  <nmwg:key id=\"key-1\">\n";
    $subject .= "    <nmwg:parameters id=\"parameters-key-1\">\n";
    $subject .= "      <nmwg:parameter name=\"maKey\">" . $cgi->param('key1') . "</nmwg:parameter>\n";
    $subject .= "    </nmwg:parameters>\n";
    $subject .= "  </nmwg:key>  \n";

    my $time = 86400;
    my $result = $ma->setupDataRequest(
        {
            start                 => ( $sec - $time ),
            end                   => $sec,
            resolution            => 5,
            consolidationFunction => "AVERAGE",
            subject               => $subject,
            eventTypes            => \@eventTypes
        }
    );

    # 'out' data
    my $subject2 = "  <nmwg:key id=\"key-2\">\n";
    $subject2 .= "    <nmwg:parameters id=\"parameters-key-2\">\n";
    $subject2 .= "      <nmwg:parameter name=\"maKey\">" . $cgi->param('key2') . "</nmwg:parameter>\n";
    $subject2 .= "    </nmwg:parameters>\n";
    $subject2 .= "  </nmwg:key>  \n";
    my $result2 = $ma->setupDataRequest(
        {
            start                 => ( $sec - $time ),
            end                   => $sec,
            resolution            => 5,
            consolidationFunction => "AVERAGE",
            subject               => $subject2,
            eventTypes            => \@eventTypes
        }
    );

    print "<html>\n";
    print "  <head>\n";
    print "    <title>perfSONAR-PS perfAdmin Utilization Graph</title>\n";
    print "    <script type=\"text/javascript\" src=\"http://www.google.com/jsapi\"></script>\n";
    print "    <script type=\"text/javascript\">\n";
    print "      google.load(\"visualization\", \"1\", {packages:[\"areachart\"]})\n";
    print "      google.setOnLoadCallback(drawChart);\n";
    print "      function drawChart() {\n";
    print "        var data = new google.visualization.DataTable();\n";
    print "        data.addColumn('date', 'Time');\n";
    print "        data.addColumn('number', 'In');\n";
    print "        data.addColumn('number', 'Out');\n";

    my $doc1 = $parser->parse_string( $result->{"data"}->[0] );
    my $datum1 = find( $doc1->getDocumentElement, "./*[local-name()='datum']", 0 );

    my $doc2 = $parser->parse_string( $result2->{"data"}->[0] );
    my $datum2 = find( $doc2->getDocumentElement, "./*[local-name()='datum']", 0 );

    if ( $datum1 and $datum2 ) {
        my $counter = 0;
        foreach my $dt ( $datum1->get_nodelist ) {
            $counter++;
        }
        print "        data.addRows(" . $counter . ");\n";

        my %store = ();
        foreach my $dt ( $datum1->get_nodelist ) {
            $store{ $dt->getAttribute("timeValue") }{"in"} = eval( $dt->getAttribute("value") );
        }
        foreach my $dt ( $datum2->get_nodelist ) {
            $store{ $dt->getAttribute("timeValue") }{"out"} = eval( $dt->getAttribute("value") );
        }

        $counter = 0;
        foreach my $time ( sort keys %store ) {
            my $date  = ParseDateString( "epoch " . $time );
            my $date2 = UnixDate( $date, "%Y-%m-%d %H:%M:%S" );
            my @array = split( / /, $date2 );
            my @year  = split( /-/, $array[0] );
            my @time  = split( /:/, $array[1] );
            print "        data.setValue(" . $counter . ", 0, new Date(" . $year[0] . "," . ( $year[1] - 1 ) . ",";
            print $year[2] . "," . $time[0] . "," . $time[1] . "," . $time[2] . "));\n";
            print "        data.setValue(" . $counter . ", 1, " . $store{$time}{"in"} . ");\n"  if $store{$time}{"in"};
            print "        data.setValue(" . $counter . ", 2, " . $store{$time}{"out"} . ");\n" if $store{$time}{"out"};
            $counter++;
        }
    }

    print "        var chart = new google.visualization.AreaChart(document.getElementById('chart_div'));\n";
    print "        chart.draw(data, {width: 900, height: 400, legend: 'bottom', title: 'Utilization'});\n";
    print "      }\n";
    print "    </script>\n";
    print "  </head>\n";
    print "  <body>\n";
    print "    <div id=\"chart_div\"></div>\n";
    print "  </body>\n";
    print "</html>\n";
}
else {
    print "<html><head><title>perfSONAR-PS perfAdmin Utilization Graph</title></head>";
    print "<body><h2 align=\"center\">Graph error; Close window and try again.</h2></body></html>";
}

__END__

=head1 SEE ALSO

L<CGI>, L<XML::LibXML>, L<Date::Manip>, L<perfSONAR_PS::Client::MA>,
L<perfSONAR_PS::Common>

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

Copyright (c) 2007-2008, Internet2

All rights reserved.

=cut

