#!/bin/env perl

use gmaps::Topology::GeoIP;


foreach my $ip ( @ARGV ) {

	my ( $lat, $long ) = &gmaps::Topology::GeoIP::getLongLat( $ip );

	print "IP $ip located at $lat, $long\n";

}

exit 1;