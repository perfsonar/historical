#!/usr/bin/perl -w -I /usr/local/perfSONAR-PS/lib -I/Users/boote/dev/perfSONAR-PS/trunk/perfSONAR-PS/lib -I/home/boote/dev/perfSONAR-PS/trunk/perfSONAR-PS/lib

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
my $port = 8080;
my $endpoint = "perfSONAR_PS/services/snmpMA";
my $filter = '//nmwg:message//nmwg:datum';

my $cgi = new CGI;

# Test mode stuff
# TODO: Modify default to false...
my $fakeServiceMode = $cgi->param('fakeServiceMode');

my $int = $cgi->param('resolution') || 5;
my $maxValue = $cgi->param('maxValue') || 10000;
my $host = $cgi->param('hostName') || "rtr129-93-239-128.unl.edu";
my $index = $cgi->param('ifIndex') || 4;
my $direction = $cgi->param('direction') || "out";
my $npoints = $cgi->param('npoints') || 5;
my $refTime = $cgi->param('refTime') || "now";



# Create JSON from datum
print $cgi->header(-type => "text/javascript",
    -expires=>'now',
    -pragma=>'no-cache');

my $sec;
if(!$fakeServiceMode){
#    warn "real data";
    $sec = getReferenceTime($refTime,1);
    print fetchPerfsonarData($host, $index, $sec, $int, $direction, $npoints);
}
else{
#    warn "fake data: $fakeServiceMode";
    $sec = getReferenceTime($refTime,0);
    print fetchFakeData($host, $index, $sec, $int, $direction, $npoints);
}

exit 0;

sub getReferenceTime{
    my($sec,$do_res_hack) = @_;
    my($frac);

    if($sec eq "now"){
        ($sec, $frac) = Time::HiRes::gettimeofday;  
    }

    $sec;
}

# XXX: $host ignored for now, not needed for fmm07
sub makeMessage {
  my($host, $index, $time, $int, $direction, $npoints) = @_;
  my $ret;
  my $stime = $time-($int*$npoints);
  my $etime = $time;

  $ret =<<"ENDMESS";
<nmwg:message type=\"SetupDataRequest\"
	      id=\"msg1\"
              xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\"
              xmlns:neterr=\"http://ggf.org/ns/nmwg/characteristic/errors/2.0/\"
              xmlns:netdisc=\"http://ggf.org/ns/nmwg/characteristic/discards/2.0/\"
              xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"
              xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\"
              xmlns:select=\"http://ggf.org/ns/nmwg/ops/select/2.0/\"
              xmlns:nmtm=\"http://ggf.org/ns/nmwg/ops/time/2.0/\"
              xmlns:snmp=\"http://ggf.org/ns/nmwg/tools/snmp/2.0/\">

  <nmwg:metadata id=\"m1\">
    <netutil:subject id=\"s1\">
      <nmwgt:interface>
        <nmwgt:ifIndex>$index</nmwgt:ifIndex>
        <nmwgt:direction>$direction</nmwgt:direction>
      </nmwgt:interface>
    </netutil:subject>

    <nmwg:eventType>http://ggf.org/ns/nmwg/characteristic/utilization/2.0</nmwg:eventType>

    <nmwg:parameters id=\"p-netutil\">
        <nmwg:parameter name=\"supportedEventType\">http://ggf.org/ns/nmwg/characteristic/utilization/2.0</nmwg:parameter>
    </nmwg:parameters>
  </nmwg:metadata>

  <nmwg:metadata id=\"m1c\">
    <select:subject id=\"sub1c\" metadataIdRef=\"m1\"/>

    <nmwg:eventType>http://ggf.org/ns/nmwg/ops/select/2.0</nmwg:eventType>

    <select:parameters id=\"mc-p1\">
      <select:parameter name=\"startTime\">$stime</select:parameter>
      <select:parameter name=\"endTime\">$etime</select:parameter>
      <select:parameter name=\"resolution\">$int</select:parameter>
      <select:parameter name=\"consolidationFunction\">AVERAGE</select:parameter>
    </select:parameters>

  </nmwg:metadata>

  <nmwg:data id=\"d1\" metadataIdRef=\"m1c\"/>
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

#    warn "Pre sender";
    my $sender = new perfSONAR_PS::Transport("/tmp/pSerror.log", "", "", $server, $port, $endpoint);
#    warn "Post sender";

    my $mess = makeMessage($host, $index, $sec, $int, $direction, $npoints);
#    warn $mess;
    my $env = $sender->makeEnvelope($mess);

#    warn "Pre send data";
    my $response = $sender->sendReceive($env);
#    warn $response;
#    warn "Post send data";

# Turn the response into an XPath object
    my $xp;
    if( UNIVERSAL::can($response, "isa") ? "1" : "0" == 1
        && $response->isa('XML::XPath')) {
        $xp = $response;        
    } else {
        $xp = XML::XPath->new( xml => $response );
    }

# pull all the snmp:datum from the response
#    warn "Pre find";
    my $nodeset = $xp->find( $filter );
#    warn "Post find";
    if($nodeset->size() <= 0) {
        die "Nothing found for xpath statement $filter.\n";
    }

    my $data =  "\{\"servdata\"\: \{\n    \"data\"\: \[\n";
    foreach my $d ($nodeset->get_nodelist) {
        my $tt = $d->getAttribute("timeType");
        my $du = $d->getAttribute("valueUnits");

        if($tt ne "unix"){
            die "Unsupported timeType in response: $tt";
        }
        if($du ne "Bps"){
            die "Unsupported valueUnits in response: $du";
        }
        my $t = int($d->getAttribute("timeValue"));
        # convert to mbps
        my $v = int($d->getAttribute("value")) * 8 / 1000000;
        next if($v eq 'nan');
        $data .= '        ['. $t. "," . $v. '],'. "\n";
    }
    $data .= "\n      \]\n    \}\n\}";

    return $data;
}
