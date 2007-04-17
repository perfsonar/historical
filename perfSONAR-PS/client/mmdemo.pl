#!/usr/bin/perl -w -I /usr/local/perfSONAR-PS/lib

use strict;
use XML::LibXML;
use Time::HiRes qw( gettimeofday );

my %info = ();
my @index1 = ("1010001", "1020001");
$info{"anna-raptor1.internet2.edu"} = \@index1;

my @index2 = ("1000004", "1020001", "1000001", "1000002", "1010001", "1010012", "1020002");
$info{"206.196.176.229"} = \@index2;


system("rm -frd results/*txt");

my @intervals = ("1","10","60");
my($sec, $frac) = Time::HiRes::gettimeofday;  
foreach my $int (sort { $a <=> $b } @intervals) {
  print $sec , "\t" , (($sec-($sec%$int))-($int*20)) , "\t" , ($sec-($sec%$int)) , "\t" , ($int) , "\t" , ($int*20) , "\n";
  
  foreach my $host (keys %info) { 
    foreach my $index(@{$info{$host}}) {

      makeMessage($host, $index, ($sec-($sec%$int)), $int);
      open(CLIENT, "cd /usr/local/perfSONAR-PS/client/ && ./client.pl --server=packrat.internet2.edu --port=8081 --endpoint=axis/services/snmpMP /tmp/test.xml |");
      my @res = <CLIENT>;
      close(CLIENT);
    
      my $string = "";
      foreach my $line (@res) {
        $string = $string . $line;
      }
  
      if($string) {
        open(WRITE, ">./results/".$host."-".$index."-".$int.".txt");
        my $parser = XML::LibXML->new();
        my $dom = $parser->parse_string($string);      
        foreach my $d ($dom->getElementsByTagNameNS("http://ggf.org/ns/nmwg/tools/snmp/2.0/", "datum")) {  
          print WRITE $d->getAttribute("time") , "," , $d->getAttribute("value") , "\n"
        }
        close(WRITE);
      }
      system("rm -frd test.xml");
    }
  }
}

sub makeMessage {
  my($host, $index, $time, $int) = @_;
  open(FILE, ">./test.xml"); 
  
  print FILE "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n";
  print FILE "<nmwg:message type=\"request\"\n";
  print FILE "	       id=\"msg1\"\n";
  print FILE "              xmlns:nmwg=\"http://ggf.org/ns/nmwg/base/2.0/\"\n";
  print FILE "              xmlns:netutil=\"http://ggf.org/ns/nmwg/characteristic/utilization/2.0/\"\n";
  print FILE "              xmlns:nmwgt=\"http://ggf.org/ns/nmwg/topology/2.0/\"\n";
  print FILE "              xmlns:select=\"http://ggf.org/ns/nmwg/ops/select/2.0/\"\n";
  print FILE "              xmlns:snmp=\"http://ggf.org/ns/nmwg/tools/snmp/2.0/\">\n";
  print FILE "  <nmwg:metadata id=\"m1\">\n";
  print FILE "    <netutil:subject id=\"s1\">\n";
  print FILE "      <nmwgt:interface>\n";
  print FILE "        <nmwgt:hostName>".$host."</nmwgt:hostName>\n";
  print FILE "        <nmwgt:ifName>".$index."</nmwgt:ifName>\n";
  print FILE "        <nmwgt:direction>in</nmwgt:direction>\n";
  print FILE "      </nmwgt:interface>\n";
  print FILE "    </netutil:subject>\n";
  print FILE "    <nmwg:parameters id=\"p1\">\n";
  print FILE "      <select:parameter name=\"time\" operator=\"gte\">".($time-($int*20))."</select:parameter>\n";
  print FILE "      <select:parameter name=\"time\" operator=\"lte\">".$time."</select:parameter>\n";     
  print FILE "      <select:parameter name=\"consolidationFunction\">AVERAGE</select:parameter>\n";  
  print FILE "      <select:parameter name=\"resolution\">".$int."</select:parameter>\n";
  print FILE "    </nmwg:parameters>\n";
  print FILE "  </nmwg:metadata>\n";
  print FILE "  <nmwg:data id=\"d1\" metadataIdRef=\"m1\"/>\n";
  print FILE "</nmwg:message>\n";
  
  close(FILE);
  return;
}
