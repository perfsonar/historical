#!/usr/bin/perl -w

#use strict;
use warnings;
use File::Which qw(which);
use Cwd;
use File::Basename;
use Time::HiRes qw(gettimeofday);

# find rrdtool (we can quit if its not here)
my @rrdtool = which('rrdtool');

if($#rrdtool > -1) {
  use RRDp;
  $RRDp::error_mode = 'catch';
  
  # get the full path to where we are
  my $dirname = getcwd;

  # are we buidling more than one?
  my $num = 1;
  $num = $ARGV[0] if $ARGV[0]; 
  
  open(STORE, ">".$dirname."/store.xml");

  print STORE "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
  print STORE "<nmwg:store  xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"\n";
  print STORE "             xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\"\n";
  print STORE "             xmlns:neterr=\"http://ggf.org/ns/nmwg/characteristic/errors/2.0/\"\n";
  print STORE "             xmlns:netdisc=\"http://ggf.org/ns/nmwg/characteristic/discards/2.0/\"\n";
  print STORE "             xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\"\n";
  print STORE "             xmlns:snmp=\"http://ggf.org/ns/nmwg/tools/snmp/2.0/\"\n";
  print STORE "             xmlns:nmtm=\"http://ggf.org/ns/nmwg/time/2.0/\">\n\n";

  # baseline time
  my($sec, $frac) = Time::HiRes::gettimeofday;

#  $dur = 86400;  # 1 day
  my $dur = 604800; # 1 week
#  $dur = 1209600; # 14 days
#  $dur = 2592000; # 1 month

#  $step = 5;
  my $step = 10;
#  $step = 30;

  # create the rrd file, have it start a full day ago though (so we can load it with data)
  print "Making sample RRD file \n";
  RRDp::start $rrdtool[0];
  RRDp::cmd "create ".$dirname."/localhost_test.rrd --start ".(($sec-($sec % 10))-$dur)." --step $step 
               DS:ifinoctets:COUNTER:10:U:U 
               DS:ifoutoctets:COUNTER:10:U:U 
               RRA:AVERAGE:0.5:1:241920 
               RRA:AVERAGE:0.5:2:120960 
               RRA:AVERAGE:0.5:6:40320 
               RRA:AVERAGE:0.5:12:20160 
               RRA:AVERAGE:0.5:24:10080 
               RRA:AVERAGE:0.5:36:6720 
               RRA:AVERAGE:0.5:48:5040 
               RRA:AVERAGE:0.5:60:4032 
               RRA:AVERAGE:0.5:120:2016";
  my $answer = RRDp::read;

  # load the (fake) data
  my $baseIn = int(rand(10000));
  my $baseOut = int(rand(10000));
  # fake new data every $step seconds
  my $start_time = (($sec-($sec % 10))-$dur)+$step;
  for(my $y = $start_time; $y <= ($sec-($sec % 10))+$step; $y+=$step) {
      if ( ($y > $start_time) and (($y-$start_time) % 10000 == 0)) {
         print "generated ".($y-$start_time)." entries\n";
      }
      $baseIn += int(rand(1000));
      $baseOut += int(rand(1000));
      my $cmd = "update ".$dirname."/localhost_test.rrd ".$y.":".$baseIn.":".$baseOut;
      RRDp::cmd $cmd;
      $answer = RRDp::read;
      last if $RRDp::error;
    }
  my $status = RRDp::end;  
  print "RRD Status \"" . $status . "\" returned on closing.\n" if($status);

  print "Building Store file with ".$num." entries \n";
  for my $x (1..$num) {
    unless($RRDp::error) {
      # make each pair
      foreach my $dir (("in", "out")) {
        print STORE "  <nmwg:metadata xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" id=\"m-".$dir."-".$x."\">\n";
        print STORE "    <netutil:subject xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\" id=\"s-".$dir."-".$x."\">\n";
        print STORE "      <nmwgt:interface xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\">\n";
        print STORE "        <nmwgt:ifAddress type=\"ipv4\">10.1.0.".$x."</nmwgt:ifAddress>\n";
        print STORE "        <nmwgt:hostName>testHost".$x."</nmwgt:hostName>\n";
        print STORE "        <nmwgt:ifName>eth".$x."</nmwgt:ifName>\n";
        print STORE "        <nmwgt:ifIndex>".$x."</nmwgt:ifIndex>\n";
        print STORE "        <nmwgt:direction>".$dir."</nmwgt:direction>\n";
        print STORE "        <nmwgt:capacity>1000000000</nmwgt:capacity>\n";
        print STORE "      </nmwgt:interface>\n";
        print STORE "    </netutil:subject>\n";
        print STORE "    <nmwg:eventType>http://ggf.org/ns/nmwg/tools/snmp/2.0</nmwg:eventType>\n";
        print STORE "    <nmwg:eventType>http://ggf.org/ns/nmwg/characteristic/utilization/2.0</nmwg:eventType>\n";
        print STORE "    <nmwg:parameters id=\"p-".$dir."-".$x."\">\n";
        print STORE "      <nmwg:parameter name=\"supportedEventType\">http://ggf.org/ns/nmwg/tools/snmp/2.0</nmwg:parameter>\n";          
        print STORE "      <nmwg:parameter name=\"supportedEventType\">http://ggf.org/ns/nmwg/characteristic/utilization/2.0</nmwg:parameter>\n";
        print STORE "    </nmwg:parameters>\n";
        print STORE "  </nmwg:metadata>\n\n";
 
        print STORE "  <nmwg:data xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\" id=\"d-".$dir."-".$x."\" metadataIdRef=\"m-".$dir."-".$x."\">\n";
        print STORE "    <nmwg:key id=\"k-".$dir."-".$x."\">\n";
        print STORE "      <nmwg:parameters id=\"pk-".$dir."-".$x."\">\n";
        print STORE "        <nmwg:parameter name=\"supportedEventType\">http://ggf.org/ns/nmwg/tools/snmp/2.0</nmwg:parameter>\n";
        print STORE "        <nmwg:parameter name=\"supportedEventType\">http://ggf.org/ns/nmwg/characteristic/utilization/2.0</nmwg:parameter>\n";             
        print STORE "        <nmwg:parameter name=\"type\">rrd</nmwg:parameter>\n";
        print STORE "        <nmwg:parameter name=\"file\">".$dirname."/localhost_test.rrd</nmwg:parameter>\n";
        print STORE "        <nmwg:parameter name=\"valueUnits\">Bps</nmwg:parameter>\n";
        print STORE "        <nmwg:parameter name=\"dataSource\">if".$dir."octets</nmwg:parameter>\n";
        print STORE "      </nmwg:parameters>\n";
        print STORE "    </nmwg:key>\n";
        print STORE "  </nmwg:data>\n\n";
      }
    }
    
    last if($RRDp::error);
  }

  print STORE "</nmwg:store>\n";

  close(STORE);
  
  if($RRDp::error) {
    system("rm -f ".$dirname."/store.xml");
    print "RRDtool has reported an error of \"" . $RRDp::error . "\".\n";
  }
}
else {
  print "RRDtool not found.\n";
}

print "Done.\n";


