#!/usr/bin/perl -w -I /usr/local/perfSONAR-PS/lib -I/Users/boote/dev/perfSONAR-PS/trunk/perfSONAR-PS/lib

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

# Test mode stuff
# TODO: Modify default to false...
my $fakeServiceMode = $cgi->param('fakeServiceMode');

my $int = $cgi->param('resolution') || 5;
my $maxValue = $cgi->param('maxValue') || 1000;
my $host = $cgi->param('hostName') || "anna-raptor1.internet2.edu";
my $index = $cgi->param('ifName') || "1010001";
my $direction = $cgi->param('direction') || "in";
my $npoints = $cgi->param('npoints') || 5;
my $refTime = $cgi->param('refTime') || "now";



# Create JSON from datum
print $cgi->header(-type => "text/javascript",
    -expires=>'now',
    -pragma=>'no-cache');

my $sec;
if(!$fakeServiceMode){
    $sec = getReferenceTime($refTime,1);
    print fetchPerfsonarData($host, $index, $sec, $int, $direction, $npoints);
}
else{
    $sec = getReferenceTime($refTime,0);
    print fetchFakeData($host, $index, $sec, $int, $direction, $npoints);
}

exit 0;

sub getReferenceTime{
    my($sec,$do_res_hack) = @_;
    my($frac);

    if($sec eq "now"){
        ($sec, $frac) = Time::HiRes::gettimeofday;  

        # XXX: Remove when SNMP_MA ignores last RRD value
#        $sec -= 10;

        # XXX: Remove when this is done by SNMP_MA
        # put on interval boundary for broken rrdtool
        if($do_res_hack && $sec%$int){
            $sec = int($sec/$int)*$int; # this is end time - so round-down
        }
    }

    $sec;
}

sub makeMessage {
  my($host, $index, $time, $int, $direction, $npoints) = @_;
  my $ret;
  my $stime = $time-($int*$npoints);
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
        <nmwgt:direction>$direction</nmwgt:direction>
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

sub fetchFakeData{
    my($host, $index, $time, $int, $direction, $npoints) = @_;

    # Randomize from 0 to maxValue
    # XXX: HERE!!!!
    my $data =  "\{\"servdata\"\: \{\n    \"data\"\: \[\n";
    my $v = rand($maxValue);
    $data .= '        ['.$time."," . $v. '],'. "\n";
    $data .= "\n      \]\n    \}\n\}";

    return $data;
}

sub fetchPerfsonarData{
    my($host, $index, $time, $int, $direction, $npoints) = @_;

    warn "Pre sender";
    my $sender = new perfSONAR_PS::Transport("/tmp/pSerror.log", "", "", $server, $port, $endpoint);
    warn "Post sender";

    my $mess = makeMessage($host, $index, $sec, $int, $direction, $npoints);
    my $env = $sender->makeEnvelope($mess);

    warn "Pre send data";
    my $response = $sender->sendReceive($env);
    warn "Post send data";

# Turn the response into an XPath object
    my $xp;
    if( UNIVERSAL::can($response, "isa") ? "1" : "0" == 1
        && $response->isa('XML::XPath')) {
        $xp = $response;        
    } else {
        $xp = XML::XPath->new( xml => $response );
    }

# pull all the snmp:datum from the response
    warn "Pre find";
    my $nodeset = $xp->find( $filter );
    warn "Post find";
    if($nodeset->size() <= 0) {
        die "Nothing found for xpath statement $filter.\n";
    }

    my $data =  "\{\"servdata\"\: \{\n    \"data\"\: \[\n";
    foreach my $d ($nodeset->get_nodelist) {
        my $t = int($d->getAttribute("time"));
        # mbps
        my $v = int($d->getAttribute("value")) * 8 / 1000000;
        next if($v eq 'nan');
        $data .= '        ['. $t. "," . $v. '],'. "\n";
    }
    $data .= "\n      \]\n    \}\n\}";

    return $data;
}
