#!/usr/bin/perl -w -I /usr/local/perfSONAR-PS/lib

use strict;
use FindBin;

use Getopt::Std;
use CGI qw/:standard -any/;
use CGI::Carp qw(fatalsToBrowser);
use XML::LibXML;
use Time::HiRes qw( gettimeofday );

use perfSONAR_PS::Transport;

# Eventually get these from config (or even app)
my $server = "packrat.internet2.edu";
my $port = 8081;
my $endpoint = "axis/services/snmpMP";
my $filter = '//nmwg:message//snmp:datum';

my $cgi = new CGI;

my $int = $cgi->param('resolution') || 10;
my $host = $cgi->param('hostName') || "anna-raptor1.internet2.edu";
my $index = $cgi->param('ifName') || "1020001";

# TODO: Set time from parameters to allow 'replay'
my($sec, $frac) = Time::HiRes::gettimeofday;  
$sec -= 10;

# put on interval boundary for broken rrdtool
if($sec%$int){
    $sec = int($sec/$int)*$int; # end time round-down
}

my $sender = new perfSONAR_PS::Transport("/tmp/pSerror.log", "", "", $server, $port, $endpoint);

my $mess = makeMessage($host, $index, $sec, $int);
my $env = $sender->makeEnvelope($mess);

my $response = $sender->sendReceive($env);

# Turn the response into an XPath object
my $xp;
if( UNIVERSAL::can($response, "isa") ? "1" : "0" == 1
    && $response->isa('XML::XPath')) {
    $xp = $response;        
} else {
    $xp = XML::XPath->new( xml => $response );
}

# pull all the snmp:datum from the response
my $nodeset = $xp->find( $filter );
if($nodeset->size() <= 0) {
    die "Nothing found for xpath statement $filter.\n";
}

# Create JSON from datum
print $cgi->header(-type => "text/javascript",
    -expires=>'now',
    -pragma=>'no-cache');

print "\{\"servdata\"\: \{\n    \"data\"\: \[\n";
foreach my $d ($nodeset->get_nodelist) {
    my $t = $d->getAttribute("time");
    my $v = $d->getAttribute("value");
    next if($v eq 'nan');
    print '        [', $t, "," , $v, '],', "\n";
}
print "\n      \]\n    \}\n\}";

exit 0;


sub makeMessage {
  my($host, $index, $time, $int) = @_;
  my $ret;
  my $stime = $time-($int*50);
  my $etime = $time;

  $ret =<<"ENDMESS";
<nmwg:message type=\"request\"
	      id=\"msg1\"
              xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"
              xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\"
              xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\"
              xmlns:select=\"http://ggf.org/ns/nmwg/ops/select/2.0/\"
              xmlns:snmp=\"http://ggf.org/ns/nmwg/tools/snmp/2.0/\">
  <nmwg:metadata id=\"m1\">
    <netutil:subject id=\"s1\">
      <nmwgt:interface>
        <nmwgt:hostName>$host</nmwgt:hostName>
        <nmwgt:ifName>$index</nmwgt:ifName>
        <nmwgt:direction>in</nmwgt:direction>
      </nmwgt:interface>
    </netutil:subject>
    <nmwg:parameters id=\"p1\">
      <select:parameter name=\"time\" operator=\"gte\">$stime</select:parameter>
      <select:parameter name=\"time\" operator=\"lte\">$etime</select:parameter>\n";     
      <select:parameter name=\"consolidationFunction\">AVERAGE</select:parameter>\n";  
      <select:parameter name=\"resolution\">$int</select:parameter>
    </nmwg:parameters>
  </nmwg:metadata>
  <nmwg:data id=\"d1\" metadataIdRef=\"m1\"/>
</nmwg:message>
ENDMESS

  return $ret;
}
