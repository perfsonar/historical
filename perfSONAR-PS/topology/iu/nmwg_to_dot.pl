#!/usr/bin/perl -w

use strict;
use XML::LibXML;

my $in = shift;
my $out = shift;

my $parser = XML::LibXML->new();
my $dom = $parser->parse_file($in);

open (WRITE, ">".$out);

print WRITE "graph g {\n";

my %nodes = ();
my %links = ();
foreach my $l ($dom->getElementsByTagNameNS("http://ggf.org/ns/nmwg/topology/base/3.0/", "link")) {
  my $ln = "";
  foreach my $n ($l->find("./nmtopo:node")->get_nodelist()) {  
    if(!defined $nodes{$n->getAttribute("id")}) {
      $nodes{$n->getAttribute("id")} = 1;
    }
    if($ln eq "") {
      $ln = $n->getAttribute("id");
    }
    else {
      $ln = $ln . "?" . $n->getAttribute("id");
    }
  }
  if(!defined ) {
    $links{$ln} = 1;
  }
}

foreach my $l (keys %links) {
  my @stuff = split(/\?/, $l);
  print WRITE "  \"".$stuff[0]."\" -- \"".$stuff[1] , "\" [ arrowhead=none, arrowtail=none ];\n";
}

print WRITE "}\n";

close(WRITE);
