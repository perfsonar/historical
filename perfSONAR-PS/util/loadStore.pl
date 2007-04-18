#!/usr/bin/perl -w -I ../lib

use strict;
use Getopt::Long;
use XML::LibXML;
use perfSONAR_PS::Common;
use perfSONAR_PS::DB::File;

my $fileName = "loadStore.pl";
my $functionName = "main";
my $DEBUG = '';
my $HELP = '';
my %opts = ();
GetOptions('verbose' => \$DEBUG,
           'help' => \$HELP,
	   'input=s' => \$opts{IN}, 
	   'output=s' => \$opts{OUT});
			 
if(!(defined $opts{IN} and $opts{OUT}) or $HELP) {
  print "$0: Cleans the input store file, and loads it into the output store file.\n";
  print "$0 [--verbose --help --input=/path/to/old.store.xml --output=/path/to/new.store.xml]\n";
  exit(1);
}

my $IN = "./store.xml";
my $OUT = "./new.store.xml";
if(defined $opts{IN}) {
  $IN = $opts{IN};
}
if(defined $opts{OUT}) {
  $OUT = $opts{OUT};
}

my %ns = (
  nmwg => "http://ggf.org/ns/nmwg/base/2.0/",
  netutil => "http://ggf.org/ns/nmwg/characteristic/utilization/2.0/",
  nmwgt => "http://ggf.org/ns/nmwg/topology/2.0/",
  snmp => "http://ggf.org/ns/nmwg/tools/snmp/2.0/",
  ping => "http://ggf.org/ns/nmwg/tools/ping/2.0/",
  select => "http://ggf.org/ns/nmwg/ops/select/2.0/"
);  

my $filedb = new perfSONAR_PS::DB::File(
  "./perfSONAR_PS.log",
  $IN,
  $DEBUG
);  
   
$filedb->openDB;   
my $dom = $filedb->getDOM(); 
$dom = chainMetadata($dom, "http://ggf.org/ns/nmwg/base/2.0/");

reEval(\%ns, $dom->getDocumentElement);

foreach my $md ($dom->getElementsByTagNameNS("http://ggf.org/ns/nmwg/base/2.0/", "metadata")) {
  my $count = countRefs($md->getAttribute("id"), $dom, "http://ggf.org/ns/nmwg/base/2.0/", "data", "metadataIdRef");
  if($count == 0) {
    $dom->getDocumentElement->removeChild($md);
  } 
}   

open(FILE, ">".$OUT);
print FILE $dom->toString();
close(FILE);

sub reEval {
  my($ns, $node) = @_;
  if($node->prefix and $node->namespaceURI()) {
    if(!($ns->{$node->prefix})) {
      foreach my $n (keys %{$ns}) {
        if($ns->{$n} eq $node->namespaceURI()) {
          $node->setNamespace($ns->{$n}, $n, 1);
          last;
        }
      }    
    }
  }
  if($node->hasChildNodes()) {
    foreach my $c ($node->childNodes) {
      if($node->nodeType != 3) {
        reEval($ns, $c);
      }
    }
  }
  return;
}

=head1 NAME

loadStore.pl - Clean up the representation of a store file.

=head1 DESCRIPTION

Given an intial store file, this script will resolve merge chains and ouput a new
store file.

=head1 SYNOPSIS

./loadStore.pl [--verbose --help --input=/path/to/old.store.xml --output=/path/to/new.store.xml]

The verbose flag allows lots of debug options to print to the screen.  Help describes a simple use
case.  The final 2 arguments are required.  

=head1 FUNCTIONS

=head2 reEval($ns, $node)

Given a hash of 'acceptable' namespaces and URIs, traverse a DOM/node replacing unacceptable
values.

=head1 REQUIRES

Getopt::Long
XML::LibXML
perfSONAR_PS::Common
perfSONAR_PS::DB::File

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
