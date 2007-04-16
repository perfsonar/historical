#!/bin/env perl

#######################################################################
# dns loc api to get info about location of an ip address
#######################################################################

use gmaps::Topology;

package gmaps::Topology::DNSLoc;

use strict;


sub getLatLong
{
	my $dns = shift;
	
	# host only supports loc of dns address
	my $ip = undef;
	if ( $dns =~ /\d+\.\d+\.\d+\.\d+/ ) {
		$ip = $dns;
		( undef , $dns) = &gmaps::Topology::getDNS( $dns );
	}
	
	return ( undef, undef ) unless ( defined $dns && $dns ne '' );
	my $uri = "host -t LOC " . $dns;

	# run
	my $out = `$uri`;

#aoacr1-oc192-chicr1.es.net location 40 43 12.000 N 74 0 18.000 W 0.00m 1m 1000m 10m

	my $long = undef;
	my $lat = undef;

	if ( $out =~ / (\d+) (\d+) (\d+\.\d+) (N|S) (\d+) (\d+) (\d+\.\d+) (E|W) / )
	{
		$lat = $1 + ($2/60) + ($3/3600);
		if ( $4 eq 'S' ) {
			$lat *= -1;
		}
		$long = $5 + ($6/60) + ($7/3600);
		if ( $8 eq 'W' ) {
			$long *= -1;
		}
	}
	undef $out;

	return ( $lat, $long  );

}


1;