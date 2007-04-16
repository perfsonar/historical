#!/bin/env perl

#######################################################################
# geoip api to get info about location of an ip address
#######################################################################

use LWP::UserAgent;

package gmaps::Topology::GeoIP;


use strict;


sub getLatLong
{
	my $ip = shift;
	my $uri = "http://www.geoiptool.com/en/?IP=" . $ip;

	# run
	my $ua = LWP::UserAgent->new();
	$ua->timeout( 3 );
	$ua->agent( 'perfSONAR-PS-gmaps/0.1');

	my $req = HTTP::Request->new( GET => $uri );
	my $res = $ua->request( $req );
	my $out = $res->content();

	my $lat = undef;
	my $long = undef;	
	if ( $out =~ /Latitude:.*\n.*\>(\-?\d+\.\d+)/m ) {
		$lat = $1;
	}
	if ( $out =~ /Longitude:.*\n.*\>(\-?\d+\.\d+)/m ) {
		$long = $1;
	}
	undef $out;
	
	return ( $lat, $long );
}


1;