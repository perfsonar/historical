#!/usr/bin/perl -w -I ../lib
# ################################################################################ #
#                                                                                  #
# Name:		loadDatabase.pl                                                    #
# Author:	Aaron Brown                                                        #
# Contact:	aaron@internet2.edu                                                #
# Args:		input file = The XML file containing the topology to add to the DB #
#               --output = Outputs the normalized topology file                    #
#               --db_dir = The directory of the Sleepycat Database                 #
#               --db_file = The filename of the database                           #
#               --uri = The uri of the MA to update                                #
# Purpose:	Load the specified topology archive with the specified topology    #
#                                                                                  #
# ################################################################################ #

use strict;
use XML::LibXML;
use File::Basename;

my $dirname;
my $libdir;

# we need to figure out what the library is at compile time so that "use lib"
# doesn't fail. To do this, we enclose the calculation of it in a BEGIN block.
BEGIN {
	$dirname = dirname($0);
	$libdir = $dirname."/../../../lib";
}

use lib "$libdir";

use perfSONAR_PS::MA::Topology::Client::XMLDB;
use perfSONAR_PS::MA::Topology::Client::MA;
use perfSONAR_PS::MA::Topology::Topology;
use perfSONAR_PS::MA::Topology::ID;
use Log::Log4perl qw(get_logger :levels);
use Getopt::Long;

my %opts;
my $help_needed;
my $DEBUGFLAG;

sub usage() {
	print "$0: loads a topology into a database replacing the existing topology elements.\n";
	print "    [--debug] [--help] [--output=NORMALIZED_TOPOLOGY_FILE] [--db_dir=DATABASE_DIRECTORY] [--db_filename=DATABASE_FILENAME] [--uri=REMOTE_TOPOLOGY_ARCHIVE] INPUT_FILE\n";
}

my $ok = GetOptions (
		'debug'    	=> \$DEBUGFLAG,
		'output=s'	=> \$opts{OUTPUT_FILE},
		'db_dir=s'  	=> \$opts{DB_DIR},
		'db_filename=s'	=> \$opts{DB_FILE},
		'uri=s'		=> \$opts{URI},
		'help'     	=> \$help_needed
	);

if (not $ok or $help_needed) {
	usage();
	exit(-1);
}

my $input_file = shift;

if (!defined $input_file or $input_file eq "" or ! -f $input_file) {
	print "Error: you must specify an existing topology input file\n";
	usage();
	exit(-2);
}

if (!defined $opts{URI} and (!defined $opts{DB_DIR} or !defined $opts{DB_FILE})) {
	print "Error: you must specify either a URI or the Database directory/filename\n";
	usage();
	exit(-3);
}

Log::Log4perl->init($dirname."/../logger.conf");

my $logger = get_logger("perfSONAR_PS::MA::Topology");

if ($DEBUGFLAG) {
	$logger->level($DEBUG);    
} else {
	$logger->level($INFO); 
}

my ($status, $res);

my $parser = XML::LibXML->new();
my $doc = $parser->parse_file($input_file);

# The MA will normalize it for us, if we're not sending to the MA, we need to
# normalize unless the user has requested the normalized topology.
if (!defined $opts{URI} or $opts{URI} eq "" or defined $opts{OUTPUT_FILE}) {
	($status, $res) =  topologyNormalize($doc->documentElement());
	if ($status != 0) {
		$logger->debug("Error normalizing topology: $res");
		exit(-1);
	}
}

if (defined $opts{OUTPUT_FILE}) {
	$doc->toFile($opts{OUTPUT_FILE});
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
	if (!-d $opts{DB_DIR}) {
		mkdir($opts{DB_DIR});
	}

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

exit(0);
