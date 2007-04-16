#!/bin/env perl


#######################################################################
# module to query and retrieve info from teh lookupservice
#######################################################################

use gmaps::gmap;
use gmaps::Transport;
use gmaps::Topology;

package gmaps::LookupService;


use strict;



###
# returns an array of ip's found on ls
###
sub getAllRouters
{
	my $lsHost = shift;
	my $lsPort = shift;
	my $lsEndpoint = shift;

	my $requestXML = ${gmaps::gmap::templatePath} . 'ls_all-router-ip-addresses.tt2';

	my $routers = &gmaps::Transport::getArray( 
		$lsHost, $lsPort, $lsEndpoint, 
		$requestXML, 
		'//nmwg:message/nmwg:data/psservice:datum/text()');

	my %seen = ();
	
	my @final = ();
	foreach my $r ( @$routers ) {
		next unless ( &gmaps::Topology::isIpAddress( $r ) );
		push @final, $r unless $seen{$r}++;
	}
	return \@final;
}


1;