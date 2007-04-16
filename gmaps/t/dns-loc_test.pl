#!/bin/env perl

use gmaps::Topology::DNSLoc;


foreach my $ip ( @ARGV ) {

	my ( $lat, $long ) = &gmaps::Topology::DNSLoc::getLongLat( $ip );

	print "IP $ip located at $lat, $long\n";

}

exit 1;