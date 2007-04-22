#!/usr/bin/perl -w -I ../lib

use strict;
use perfSONAR_PS::Transport;
use perfSONAR_PS::Common qw( readConfiguration readXML);
use XML::XPath;
use Getopt::Long;

my $fileName = "echoCheck.pl";
my $functionName = "main";
my $DEBUG = '';
my $HELP = '';
my $status = GetOptions ('verbose' => \$DEBUG,
                         'help' => \$HELP);

if(!$status or $HELP) {
  print "$0: starts the snmp MP and MA.\n";
  print "\t$0 [--verbose --help]\n";
  exit(1);
}

my %conf = ();
readConfiguration("./echoCheck.conf", \%conf);

my $xml = readXML($conf{"MESSAGE"});

my $sender = new perfSONAR_PS::Transport("./error.log", "", "", 
$conf{"SERVER"}, $conf{"PORT"}, $conf{"ENDPOINT"}, "0");

my $envelope = $sender->makeEnvelope($xml);
my $responseContent = $sender->sendReceive($envelope);

my $bad = 1;
if(!($responseContent =~ m/^500.*/)) {
  my $xp = XML::XPath->new(xml => $responseContent);   
  $xp->set_namespace("nmwg", "http://ggf.org/ns/nmwg/base/2.0/");
  my $nodeset = $xp->find("//nmwg:message/nmwg:metadata/nmwg:eventType");
  if($nodeset->size() == 1) {
    if($nodeset->get_node(1)->getChildNode(1)->string_value eq "success.echo") {
      $bad = 0;
    }
  }
}

if($bad) {
  $conf{"PROGRAM"} =~ s/\"//g;
  open(IN, "ps axw |");
  while(<IN>) {
    if (/$conf{"PROGRAM"}/) {
      my $pid = $_;
      $pid =~ s/\?.*//;
      $pid =~ s/\s+//g;
      system("kill -9 " . $pid);
      last;
    }
  }
  close(IN);
  system("cd ".$conf{"DIR"}." && ./".$conf{"EXE"});
}
