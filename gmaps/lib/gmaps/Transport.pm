#!/bin/env perl

#######################################################################
# handles all transport/communications with perfsonar services
#######################################################################

use perfSONAR_PS::Transport;
use perfSONAR_PS::Common qw( readXML );

package gmaps::Transport;

use strict;



sub get
{
	my $host = shift;
	my $port = shift;
	my $endpoint = shift;
	
	my $request = shift; # xml file or string
	my $filter = shift;	# xpath

	if ( $filter eq '' ) {
		$filter = '/';
	}

	# start a transport agent
	my $sender = new perfSONAR_PS::Transport("/dev/null", "", "", $host, $port, $endpoint);

	# get the xml
	my $xml = undef;
	if ( -e $request ) {
		$request = &perfSONAR_PS::Common::readXML( $request );
	}
	
	# Make a SOAP envelope, use the XML file as the body.
	my $envelope = $sender->makeEnvelope($request);
	
	# Send/receive to the server, store the response for later processing
	my $response = $sender->sendReceive($envelope);

	# usie the xpath statement if necessary
   	my $xp = XML::XPath->new( xml => $response );

    my $nodeset = $xp->find( $filter );
    if($nodeset->size() <= 0) {
		die "Nothing found for xpath statement $filter.\n";
    }
    
	return $nodeset;
}


sub getArray
{
	my $host = shift;
	my $port = shift;
	my $endpoint = shift;
	
	my $request = shift; # xml file
	my $filter = shift;	# xpath
		
	my $nodeset = &get( $host, $port, $endpoint, $request, $filter );
	
	# For now, print out the result message
	my @out = undef;
    foreach my $node ($nodeset->get_nodelist) {
        push @out, XML::XPath::XMLParser::as_string($node);
    }
    
    return \@out;
}

sub getString
{
	my $host = shift;
	my $port = shift;
	my $endpoint = shift;
	
	my $request = shift; # xml file
	my $filter = shift;	# xpath
		
	my $array = &getArray( $host, $port, $endpoint, $request, $filter );

	return "@$array";
}


1;