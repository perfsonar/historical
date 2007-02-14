#!/usr/bin/perl -w -I ../lib

# ################################################### #
#                                                     #
# Author:   Jason Zurawski (zurawski@eecis.udel.edu)  #
# Title:    client.pl                                 #
# Purpose:  Send an XML message, based on the NM-WG   #
#           format to a participating server.         #
# Last Modified:                                      #
#           05/15/06                                  #
#                                                     #
# ################################################### #

use strict;
use perfSONAR_PS::Transport;
use perfSONAR_PS::Common qw( readXML );
use Getopt::Long;

our $DEBUG = 2;
our $HOST = "localhost";
our $PORT = "5000";
our $ENDPOINT = '/axis/services/MP';

our $help_needed;

my $ok = GetOptions ('debug'    	=> \$DEBUG,
                     'server=s'		=> \$HOST,
		     'port=s'  		=> \$PORT,
		     'endpoint=s'	=> \$ENDPOINT,
                     'help'     	=> \$help_needed);

if(not $ok or $help_needed ) {
  print "$0: sends an xml file to the server on specified port.\n";
  print "    ./client.pl --server=xxx.yyy.zzz --port=n --endpoint=ENDPOINT  FILENAME \n";
  exit(1);
}

my $sender = new perfSONAR_PS::Transport("", "", $PORT, $HOST, $ENDPOINT);

					# Read the source XML file
my $xml = readXML($ARGV[0]);
					# Make a SOAP envelope, use the XML file
					# as the body.
my $envelope = $sender->makeEnvelope($xml);
					# Send/receive to the server, store the 
					# response for later processing
my $responseContent = $sender->sendReceive($envelope);

					# Use XPath to extract just the message
					# message element.
my $xp = XML::XPath->new( xml => $responseContent );
$xp->clear_namespaces();
$xp->set_namespace('nmwg', 'http://ggf.org/ns/nmwg/base/2.0/');
my $nodeset = $xp->find('//nmwg:message');
if($nodeset->size() <= 0) {
  $nodeset = $xp->find('//message');
}
					# For now, print out the result message
if($DEBUG) {
  foreach my $node ($nodeset->get_nodelist) {
    print XML::XPath::XMLParser::as_string($node) , "\n";
  }
}

exit(0);
