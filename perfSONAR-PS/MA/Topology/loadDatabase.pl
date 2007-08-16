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
use perfSONAR_PS::MA::Topology::Client::MA;
use perfSONAR_PS::MA::Topology::Topology;
use perfSONAR_PS::MA::Topology::ID;
use Log::Log4perl qw(get_logger :levels);
use Getopt::Long;

Log::Log4perl->init("logger.conf");

my %opts;
my $help_needed;
my $DEBUG;

my $ok = GetOptions (
		'debug'    	=> \$DEBUG,
		'output=s'	=> \$opts{OUTPUT_FILE},
		'db_dir=s'  	=> \$opts{DB_DIR},
		'db_filename=s'	=> \$opts{DB_FILENAME},
		'uri=s'		=> \$opts{URI},
		'help'     	=> \$help_needed
	);

my $input_file = shift;


if (!defined $input_file or $input_file eq "") {
	print "Error: you must specify a topology input file\n";
	$help_needed = 1;
}

if (!defined $opts{URI} and (!defined $opts{DB_DIR} or !defined $opts{DB_FILENAME})) {
	print "Error: you must specify either a URI or the Database directory/filename\n";
	$help_needed = 1;
}

if (not $ok or $help_needed) {
	print "$0: loads a topology into a database replacing the existing topology elements.\n";
	print "    [--output=NORMALIZED_TOPOLOGY_FILE] [--db_dir=DATABASE_DIRECTORY] [--db_filename=DATABASE_FILENAME] [--uri=REMOTE_TOPOLOGY_ARCHIVE] INPUT_FILE\n";
	exit(-1);
}

my $logger = get_logger("perfSONAR_PS::MA::Topology");
my ($status, $res);

my $parser = XML::LibXML->new();
my $doc = $parser->parse_file($input_file);

if (defined $opts{OUTPUT_FILE}) {
	($status, $res) =  topologyNormalize($doc->documentElement());
	if ($status != 0) {
		$logger->debug("Error normalizing topology: $res");
		exit(-1);
	}
}

my %ns;

%ns = getTopologyNamespaces();

# we probably should collect all the namespaces here
my @namespaces = $doc->documentElement()->getNamespaces();
foreach my $namespace (@namespaces) {
	$ns{$namespace->prefix} = $namespace->getNamespaceURI;
}

my $client;
if (defined $opts{URI}) {
	$client = new perfSONAR_PS::MA::Topology::Client::MA($opts{URI});
} else {
	$client = new perfSONAR_PS::MA::Topology::Client::XMLDB($opts{DB_DIR}, $opts{DB_FILE}, \%ns);
}

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

if (defined $opts{OUTPUT_FILE}) {
	$doc->toFile($opts{OUTPUT_FILE});
}

exit(0);
