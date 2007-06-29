#!/usr/bin/perl -w -I ../lib

use strict;
use perfSONAR_PS::DB::XMLDB;
use Data::Dumper;

my $name = "/home/jason/LS/perfSONAR-PS/LS/xmldb";
my $store = "store.dbxml";
my $control = "control.dbxml";

my %ns = (
  nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
  netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
  nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
  snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/",
  select => "http://ggf.org/ns/nmwg/ops/select/2.0/",
  perfsonar => "http://ggf.org/ns/nmwg/tools/org/perfsonar/1.0/",
  psservice => "http://ggf.org/ns/nmwg/tools/org/perfsonar/service/1.0/"   
);

my $metadatadb = new perfSONAR_PS::DB::XMLDB($name, $store, \%ns);
$metadatadb->openDB; 
	      
my $controldb = new perfSONAR_PS::DB::XMLDB($name, $control, \%ns);
$controldb->openDB; 

print "Store Database:\n";

my @resultsString = $metadatadb->query("/nmwg:metadata");   
if($#resultsString != -1) {
  for(my $x = 0; $x <= $#resultsString; $x++) {	
    print $resultsString[$x] , "\n";
  } 
}
else {
  print "\tNo Results.\n"
}

@resultsString = $metadatadb->query("/nmwg:data");   
if($#resultsString != -1) {
  for(my $x = 0; $x <= $#resultsString; $x++) {	
    print $resultsString[$x] , "\n";
  } 
}
else {
  print "\tNo Results.\n"
}

print "\n\nControl Database:\n";

@resultsString = $controldb->query("/nmwg:metadata");   
if($#resultsString != -1) {
  for(my $x = 0; $x <= $#resultsString; $x++) {	
    print $resultsString[$x] , "\n";
  } 
}
else {
  print "\tNo Results.\n"
}

