#!/bin/env perl

use gmaps::LookupService;
use gmaps::Topology::GeoIP;
use gmaps::Topology;
use gmaps::KML;

#######################################################################
# simpel script to poll an ls for all ip routers and plot them using
# google maps with info of long/lat form geoip
#######################################################################


# fetch ips
my $routers = &gmaps::LookupService::getAllRouters(  
						'selena.acad.bg',
						'8070',
						'/axis/services/LookupService' );
#						'loco4.man.poznan.pl',
#						'8090',
#						'/axis/services/LookupService' );

my $kml = gmaps::KML->new( ${gmaps::LookupService::basedir} );

foreach my $ip (@$routers) {

	my ( $long, $lat ) = &gmaps::Topology::GeoIP::getLatLong( $ip );
	
	next if ( $lat eq undef || $long eq undef );
	
	# get the ip address and dns
	my ( $ip2, $dns ) = gmaps::Topology::getDNS( $ip );
	
	# get the descr
	my $desc = $kml->getDescr( $ip );
	
	# add the placemark
	$kml->addPlacemark( $dns, $long, $lat, $desc );

}

# draw!
my $markup = $kml->getKML();

# deref
print $$markup;

exit;
