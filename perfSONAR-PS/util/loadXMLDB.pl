#!/usr/bin/perl -w -I ../lib

use strict;
use Getopt::Long;
use XML::LibXML;
use perfSONAR_PS::DB::XMLDB;

my $fileName = "loadXMLDB.pl";
my $functionName = "main";
my $DEBUG = '';
my $HELP = '';
my %opts = ();
GetOptions('verbose' => \$DEBUG,
           'help' => \$HELP,
	   'environment=s' => \$opts{ENV}, 
	   'container=s' => \$opts{CONT}, 
	   'filename=s' => \$opts{FILE});
			 
if(!(defined $opts{ENV} and $opts{CONT} and $opts{FILE}) or $HELP) {
  print "$0: Loads into the specified container in the XML DB environment the contents of the store file.\n";
  print "$0 [--verbose --help --environment=/path/to/env/xmldb --container=container.dbxml --filename=/path/to/store.xml]\n";
  exit(1);
}

my $XMLDBENV = "./xmldb/";
my $XMLDBCONT = "store.dbxml";
my $XMLFILE = "./store.xml";
if(defined $opts{ENV}) {
  $XMLDBENV = $opts{ENV};
}
if(defined $opts{CONT}) {
  $XMLDBCONT = $opts{CONT};
}
if(defined $opts{FILE}) {
  $XMLFILE = $opts{FILE};
}

my %ns = (
  nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
  netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
  nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
  snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/",
  ping => "http://ggf.org/ns/nmwg/tools/ping/2.0/",
  select => "http://ggf.org/ns/nmwg/ops/select/2.0/"
);  
  
my $metadatadb = new perfSONAR_PS::DB::XMLDB(
  "./perfSONAR_PS.log",
  $XMLDBENV, 
  $XMLDBCONT,
  \%ns,
  $DEBUG
);

$metadatadb->openDB;

my $parser = XML::LibXML->new();
my $dom = $parser->parse_file($XMLFILE);

$dom = chainMetadata($dom);
$dom = removeMetadata($dom);

load($dom, $ns{"nmwg"}, "metadata");
load($dom, $ns{"nmwg"}, "data");



sub load {
  my($dom, $uri, $element) = @_;
  my @nodelist = $dom->getElementsByTagNameNS($uri, $element);
  foreach my $node (@nodelist) {
    my $id  = $node->getAttribute("id");
    if(defined $id and $id ne "") {  
      my @results = $metadatadb->query("//".lookup($uri, "nmwg").":".$element."[\@id=\"".$id."\"]");
      if($#results == -1) {
        print "Loading ".$element.":\t" , $node->toString() , "\n" if($DEBUG);
        $metadatadb->insertIntoContainer($node->toString(), $id);
      }
      else {
        print $element . " block \"". $id ."\" already in XMLDB.\n" if($DEBUG);
      }
    }
  }
  return;
}

sub lookup {
  my($uri, $default) = @_;
  my $prefix = "";
  foreach my $n (keys %ns) {
    if($uri eq $ns{$n}) {
      $prefix = $n;
      last;
    }
  }
  $prefix = $default if($prefix eq "");
  return $prefix;
}

sub chainMetadata {
  my($dom) = @_;
  my @nodelist = $dom->getElementsByTagNameNS($ns{"nmwg"}, "metadata");
  foreach my $node (@nodelist) {
    my @nodelist2 = $node->getElementsByLocalName("subject");
    if($nodelist2[0]) {
      if($nodelist2[0]->getAttribute("metadataIdRef")) {
        foreach my $node2 (@nodelist) {
	  if($nodelist2[0]->getAttribute("metadataIdRef") eq $node2->getAttribute("id")) {
            chain($node2, $node, $node2);
	  }
        }
      }
    }
  }
  return $dom;
}

sub chain {
  my($node, $ref, $ref2) = @_;
  if($node->nodeType != 3) {
    my $attrString = "";
    my $counter = 0;
    foreach my $attr ($node->attributes) {
      if($attr->isa('XML::LibXML::Attr')) {
        if($attr->getName ne "id" and !($attr->getName =~ m/.*idRef$/)) {
          if($counter == 0) {  
            $attrString = $attrString . "@" . $attr->getName . "=\"" . $attr->getValue . "\"";
          }
          else {
            $attrString = $attrString . " and @" . $attr->getName . "=\"" . $attr->getValue . "\"";
          }
          $counter++;
        }
      }
    }
    
    if($node->hasChildNodes()) {
      my @children = $node->childNodes;
      if($#children == 0) {
        if($node->firstChild->nodeType == 3) {        
          (my $value = $node->firstChild->textContent) =~ s/\s*//g;
          if($value) {
            if($counter == 0) {
              $attrString = $attrString . "text()=\"" . $value . "\"";
            }
            else {
              $attrString = $attrString . " and text()=\"" . $value . "\"";
            }      
          }        
        }
      }
    }
    
    if($attrString) {
      $attrString = "[".$attrString."]";      
    }
    
    (my $path = $node->nodePath()) =~ s/\/nmwg:store\/nmwg:metadata//;
    $path =~ s/\[\d\]//g;
    $path =~ s/^\///g;  
    
    if($path) {  
      if(!($ref->find($path.$attrString))) {
	my $name = $node->nodeName;
	my $path2 = $path;
	$path2 =~ s/\/$name$//;	  
	$ref->find($path2)->get_node(1)->addChild($node->cloneNode(1));	  
      }
    }
  
    if($node->hasChildNodes()) {
      foreach my $c ($node->childNodes) {
        chain($c, $ref, $ref2);
      }
    }
  }
  return;
}

sub removeMetadata {
  my($dom) = @_;

  my @metadataNodelist = $dom->getElementsByTagNameNS($ns{"nmwg"}, "metadata");
  my @dataNodelist = $dom->getElementsByTagNameNS($ns{"nmwg"}, "data");
  my $root = $dom->documentElement();
  foreach my $md (@metadataNodelist) {
    my $flag = 0;
    foreach my $d (@dataNodelist) {
      if($d->getAttribute("metadataIdRef") eq $md->getAttribute("id")) {
        $flag = 1;
        last;
      }
    }
    if(!$flag) {
      $root->removeChild($md);
    }
  }
  return $dom;
}

=head1 NAME

loadXMLDB.pl - Given some information about an XML database (environment, container) and 
a file containing metadata information (a 'store') load the appropriate elements.

=head1 DESCRIPTION

It is desirable to describe a store file in text, and then load the resulting XML into
an XML database.  This script will take necessary information (db environment, container, 
as well as a file name) and load the information as appropriate.  

=head1 SYNOPSIS

./loadXMLDB.pl [--verbose --help --environment=/path/to/env/xmldb --container=container.dbxml 
--filename=/path/to/store.xml]

The verbose flag allows lots of debug options to print to the screen.  Help describes a simple use
case.  The final 3 arguments are required.  

=head1 FUNCTIONS

=head2 load($dom, $uri, $element)

Given a DOM object, a URI, and the name of an element, extract all elements
fitting the description from the DOM and insert them into the xml db


=head2 lookup($uri, $default)

Lookup the prefix value for a given URI in the NS hash.  If not found, supply a 
simple deafult.


=head2 chainMetadata($dom)

Given a DOM, will [merge] chain all metadata elements.  Uses the 'chain' function
as a helper.


=head2 chain($node, $ref, $ref2)

Helper function to [merge] chain together 2 like elements.


=head2 removeMetadata($dom)

Removes metadata elements that do not have a corresponding data block.


=head1 REQUIRES

Getopt::Long
XML::LibXML
perfSONAR_PS::DB::XMLDB

=head1 AUTHOR

Jason Zurawski <zurawski@internet2.edu>

=head1 VERSION

$Id$

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Jason Zurawski

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
