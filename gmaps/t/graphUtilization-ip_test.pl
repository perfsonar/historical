#!/bin/env perl

use gmaps::LookupService;
use gmaps::Topology;
use gmaps::MA::RRDMA;

my $ip = $ARGV[0];

my ( $ip, $dns ) = &gmaps::Topology::getDNS( $ip );

my ( $host, $port, $endpoint, $eventType ) = &gmaps::LookupService::getMA( $ip );

unless ( defined $host )
{
	die "Could not map MA\n";	
	
}

my $routerInfo = &gmaps::MA::RRDMA::getUtilization(  
					$host,
					$port,
					$endpoint,						
					$ip,
					$eventType );

my $meta = &gmaps::MA::RRDMA::getMetadata( $routerInfo );

	# dereference graph
print ${&gmaps::MA::RRDMA::getGraph( $routerInfo, $meta )}; 

1;