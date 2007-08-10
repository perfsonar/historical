#!/usr/bin/perl -w -I ../../lib
# ################################################ #
#                                                  #
# Name:		loadDatabase.pl                    #
# Author:	Aaron Brown                        #
# Contact:	aaron@internet2.edu                #
# Args:		$ifile = Input File                #
#               $XMLDBENV = XML DB environment     #
#               $XMLDBCONT = XML DB Container      #
#               $ofile = Output File (not required)#
# Purpose:	Load the XML DB with toplogy       #
#               information                        #
#                                                  #
# ################################################ #

use XML::LibXML;
use strict;
use Data::Dumper;
use perfSONAR_PS::MA::Topology::Client::XMLDB;
use perfSONAR_PS::MA::Topology::Topology;
use perfSONAR_PS::MA::Topology::ID;
use Log::Log4perl qw(get_logger :levels);

Log::Log4perl->init("logger.conf");

my $ifile = shift;
my $xmldbenv = shift;
my $xmldbcontainer = shift;
my $ofile = shift;
my $logger = get_logger("perfSONAR_PS::MA::Topology");

if (!defined $ifile or !defined $xmldbenv or !defined $xmldbcontainer) {
	$logger->debug("Error: need to specify input file, xml db environment andxml db container. Also, if you want a file to output the munged XML into");
	exit(-1);
}

my $parser = XML::LibXML->new();
my $doc = $parser->parse_file($ifile);

my ($status, $res) =  topologyNormalize($doc->documentElement());
if ($status ne "") {
	$logger->debug("Error parsing topology: $res");
	exit(-1);
}

my %ns;

# we probably should collect all the namespaces here
my @namespaces = $doc->documentElement()->getNamespaces();
foreach my $namespace (@namespaces) {
	$ns{$namespace->prefix} = $namespace->getNamespaceURI;
}

my $client = new perfSONAR_PS::MA::Topology::Client::XMLDB($xmldbenv, $xmldbcontainer, \%ns);
($status, $res) = $client->open;
if ($status != 0) {
	$logger->debug("Couldn't open requested database");
	exit(-1);
}

($status, $res) = $client->changeTopology("replace", $doc->documentElement());
if ($status != 0) {
	print "Error adding topology: $res\n";
	exit(-1);
}

if (defined $ofile) {
	$doc->toFile($ofile);
}

exit(0);
